// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, RandomAccessFile;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zydus_vistaar/config.dart';

/// All POD file uploads use Flutter → Azure Blob (no Laravel multipart).
const int kDirectBlobThresholdBytes = 0;

/// Legacy threshold reference (10 MB) — kept for docs; uploads always use blob.
const int kDirectBlobFallbackThresholdBytes = 10 * 1024 * 1024;

/// Use block upload (not single PUT) above this size. Single PUT loads the
/// entire file into RAM — on Flutter Web that throws "Invalid array length"
/// for files ~100 MB+.
const int kAzureSinglePutMaxBytes = 4 * 1024 * 1024;

/// Azure block-blob chunk size (4 MB per block).
const int kAzureBlockSizeBytes = 4 * 1024 * 1024;

const String _kBlobResumeKeyPrefix = 'pod_blob_upload_resume_';

class BlobUploadProgress {
  final String uploadId;
  final int bytesUploaded;
  final int totalBytes;
  final double percent;
  final String stage; // preparing | uploading | finalizing | done
  final Duration? estimatedRemaining;

  const BlobUploadProgress({
    required this.uploadId,
    required this.bytesUploaded,
    required this.totalBytes,
    required this.percent,
    required this.stage,
    this.estimatedRemaining,
  });
}

class BlobUploadResult {
  final bool success;
  final int? podUploadBatchId;
  final String? batchId;
  final String? externalBatchId;
  final String? message;
  final String? error;
  final int statusCode;

  const BlobUploadResult({
    required this.success,
    required this.statusCode,
    this.podUploadBatchId,
    this.batchId,
    this.externalBatchId,
    this.message,
    this.error,
  });

  factory BlobUploadResult.fromJson(int statusCode, Map<String, dynamic> json) {
    return BlobUploadResult(
      success: (json['success'] ?? false) == true,
      statusCode: statusCode,
      podUploadBatchId: json['pod_upload_batch_id'] is int
          ? json['pod_upload_batch_id'] as int
          : int.tryParse(json['pod_upload_batch_id']?.toString() ?? ''),
      batchId: json['batch_id']?.toString(),
      externalBatchId: json['external_batch_id']?.toString(),
      message: json['message']?.toString(),
      error: json['error']?.toString(),
    );
  }
}

/// Direct Azure Blob uploader for POD files (PDF / images).
///
/// 1. POST /blob-upload/init  → write SAS URL
/// 2. PUT (or block upload) to Azure
/// 3. POST /blob-upload/complete → Laravel dispatches OCR job
class BlobDirectUploader {
  final String authToken;
  final Map<String, dynamic> context;
  final void Function(BlobUploadProgress progress)? onProgress;
  final int blockSize;
  final int maxRetriesPerBlock;
  final Duration blockUploadTimeout;

  BlobDirectUploader({
    required this.authToken,
    this.context = const {},
    this.onProgress,
    this.blockSize = kAzureBlockSizeBytes,
    this.maxRetriesPerBlock = 4,
    this.blockUploadTimeout = const Duration(minutes: 45),
  });

  Uri get _initUri =>
      Uri.parse('${API_BASE_URL}split-file-processor/blob-upload/init');
  Uri get _completeUri =>
      Uri.parse('${API_BASE_URL}split-file-processor/blob-upload/complete');
  Uri get _blockUri =>
      Uri.parse('${API_BASE_URL}split-file-processor/blob-upload/block');

  String _generateUploadId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand1 = (now ^ 0x5A827999) & 0xFFFFFFFF;
    final rand2 = (now * 0x9E3779B9) & 0xFFFFFFFF;
    String hex(int v, int width) =>
        v.toRadixString(16).padLeft(width, '0').substring(0, width);
    return '${hex(now & 0xFFFFFFFF, 8)}-${hex(rand1 & 0xFFFF, 4)}-4${hex((rand2 >> 4) & 0xFFF, 3)}-${hex(((rand2 >> 16) & 0x3FFF) | 0x8000, 4)}-${hex(rand1, 8)}${hex(rand2 & 0xFFFF, 4)}';
  }

  Future<BlobUploadResult> upload(File file) async {
    final fileName = file.path.split(RegExp(r'[/\\]')).last;
    final fileSize = await file.length();
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      return await _runUpload(
        fileName: fileName,
        fileSize: fileSize,
        readRange: (int start, int length) async {
          await raf!.setPosition(start);
          return await raf.read(length);
        },
      );
    } finally {
      await raf?.close();
    }
  }

  Future<BlobUploadResult> uploadBytes({
    required String fileName,
    required Uint8List bytes,
  }) async {
    return _runUpload(
      fileName: fileName,
      fileSize: bytes.length,
      readRange: (int start, int length) async {
        final end = start + length;
        final safeEnd = end > bytes.length ? bytes.length : end;
        if (start >= safeEnd) {
          return Uint8List(0);
        }
        return Uint8List.sublistView(bytes, start, safeEnd);
      },
    );
  }

  Future<BlobUploadResult> _runUpload({
    required String fileName,
    required int fileSize,
    required Future<Uint8List> Function(int start, int length) readRange,
  }) async {
    if (fileSize <= 0) {
      return const BlobUploadResult(
        success: false,
        statusCode: 0,
        error: 'empty_file',
        message: 'File is empty.',
      );
    }

    final uploadId = _generateUploadId();
    _emit(uploadId, 0, fileSize, 'preparing');

    final initBody = <String, dynamic>{
      'upload_id': uploadId,
      'original_file_name': fileName,
      'original_file_size': fileSize,
      'client_platform': kIsWeb ? 'web' : 'mobile',
      ...context,
    };

    http.Response initResp;
    try {
      initResp = await http.post(
        _initUri,
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(initBody),
      );
    } catch (e) {
      return BlobUploadResult(
        success: false,
        statusCode: 0,
        error: 'init_network_error',
        message: e.toString(),
      );
    }

    Map<String, dynamic> initJson;
    try {
      initJson = jsonDecode(initResp.body) as Map<String, dynamic>;
    } catch (_) {
      return BlobUploadResult(
        success: false,
        statusCode: initResp.statusCode,
        error: 'init_invalid_json',
        message: initResp.body,
      );
    }

    if (initResp.statusCode != 200 || initJson['success'] != true) {
      return BlobUploadResult.fromJson(initResp.statusCode, initJson);
    }

    if (initJson['status'] == 'completed') {
      return BlobUploadResult.fromJson(initResp.statusCode, initJson);
    }

    final sessionUploadId = initJson['upload_id']?.toString() ?? uploadId;
    final uploadMode = initJson['upload_mode']?.toString() ?? 'direct';
    final useProxy = uploadMode == 'proxy';
    final uploadUrl = initJson['upload_url']?.toString() ?? '';
    final uploadMethod = initJson['upload_method']?.toString() ?? 'put';
    final serverBlockSize =
        (initJson['block_size_bytes'] as num?)?.toInt() ?? blockSize;
    final contentType =
        initJson['content_type']?.toString() ?? _inferContentType(fileName);

    if (!useProxy && uploadUrl.isEmpty) {
      return const BlobUploadResult(
        success: false,
        statusCode: 0,
        error: 'missing_upload_url',
        message: 'Server did not return an Azure upload URL.',
      );
    }

    await _writeResumeId(fileName, sessionUploadId);

    final uploadStarted = DateTime.now();
    // Never single-PUT large files — especially on Flutter Web where loading
    // 100 MB+ into one http body throws "Invalid array length".
    final useBlockUpload = uploadMethod == 'block'
        || fileSize > kAzureSinglePutMaxBytes
        || kIsWeb;

    try {
      if (useProxy) {
        await _uploadBlockBlobViaProxy(
          sessionUploadId: sessionUploadId,
          fileSize: fileSize,
          blockSize: serverBlockSize,
          readRange: readRange,
          uploadStarted: uploadStarted,
        );
      } else if (useBlockUpload) {
        await _uploadBlockBlob(
          uploadUrl: uploadUrl,
          fileSize: fileSize,
          blockSize: serverBlockSize,
          readRange: readRange,
          uploadId: sessionUploadId,
          uploadStarted: uploadStarted,
          contentType: contentType,
        );
      } else {
        await _uploadSinglePut(
          uploadUrl: uploadUrl,
          fileSize: fileSize,
          readRange: readRange,
          uploadId: sessionUploadId,
          uploadStarted: uploadStarted,
          contentType: contentType,
        );
      }
    } catch (e) {
      return BlobUploadResult(
        success: false,
        statusCode: 0,
        error: 'azure_upload_failed',
        message: e.toString(),
      );
    }

    _emit(sessionUploadId, fileSize, fileSize, 'finalizing');

    http.Response completeResp;
    try {
      completeResp = await http.post(
        _completeUri,
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'upload_id': sessionUploadId}),
      );
    } catch (e) {
      return BlobUploadResult(
        success: false,
        statusCode: 0,
        error: 'complete_network_error',
        message: e.toString(),
      );
    }

    Map<String, dynamic> completeJson;
    try {
      completeJson = jsonDecode(completeResp.body) as Map<String, dynamic>;
    } catch (_) {
      return BlobUploadResult(
        success: false,
        statusCode: completeResp.statusCode,
        error: 'complete_invalid_json',
        message: completeResp.body,
      );
    }

    if (completeResp.statusCode == 200 && completeJson['success'] == true) {
      await _clearResumeId(fileName);
      _emit(sessionUploadId, fileSize, fileSize, 'done');
    }

    return BlobUploadResult.fromJson(completeResp.statusCode, completeJson);
  }

  Future<void> _uploadBlockBlobViaProxy({
    required String sessionUploadId,
    required int fileSize,
    required int blockSize,
    required Future<Uint8List> Function(int start, int length) readRange,
    required DateTime uploadStarted,
  }) async {
    final totalBlocks = (fileSize / blockSize).ceil();
    int bytesSent = 0;

    for (int index = 0; index < totalBlocks; index++) {
      final start = index * blockSize;
      final length =
          (start + blockSize > fileSize) ? fileSize - start : blockSize;
      final blockId = _blockId(index);
      final data = await readRange(start, length);

      for (int attempt = 0; attempt < maxRetriesPerBlock; attempt++) {
        try {
          final req = http.MultipartRequest('POST', _blockUri);
          req.headers['Authorization'] = 'Bearer $authToken';
          req.fields['upload_id'] = sessionUploadId;
          req.fields['block_index'] = index.toString();
          req.fields['block_id'] = blockId;
          req.files.add(http.MultipartFile.fromBytes(
            'chunk',
            data,
            filename: 'block_$index.bin',
          ));

          final streamed = await req.send().timeout(blockUploadTimeout);
          final resp = await http.Response.fromStream(streamed);

          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            bytesSent += length;
            _emit(sessionUploadId, bytesSent, fileSize, 'uploading',
                started: uploadStarted);
            break;
          }

          Map<String, dynamic>? body;
          try {
            body = jsonDecode(resp.body) as Map<String, dynamic>;
          } catch (_) {}

          if (attempt == maxRetriesPerBlock - 1) {
            throw Exception(
              'Proxy block $index failed: HTTP ${resp.statusCode} '
              '${body?['message'] ?? resp.body}',
            );
          }
        } on TimeoutException {
          if (attempt == maxRetriesPerBlock - 1) rethrow;
        }
        await Future<void>.delayed(Duration(seconds: 2 << attempt));
      }
    }
  }

  Future<void> _uploadSinglePut({
    required String uploadUrl,
    required int fileSize,
    required Future<Uint8List> Function(int start, int length) readRange,
    required String uploadId,
    required DateTime uploadStarted,
    required String contentType,
  }) async {
    final bytes = await readRange(0, fileSize);
    for (int attempt = 0; attempt < maxRetriesPerBlock; attempt++) {
      try {
        final resp = await http
            .put(
              Uri.parse(uploadUrl),
              headers: {
                'x-ms-blob-type': 'BlockBlob',
                'Content-Type': contentType,
              },
              body: bytes,
            )
            .timeout(blockUploadTimeout);
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          _emit(uploadId, fileSize, fileSize, 'uploading',
              started: uploadStarted);
          return;
        }
        if (attempt == maxRetriesPerBlock - 1) {
          throw Exception('Azure PUT failed: HTTP ${resp.statusCode}');
        }
      } on TimeoutException {
        if (attempt == maxRetriesPerBlock - 1) rethrow;
      }
      await Future<void>.delayed(Duration(seconds: 2 << attempt));
    }
  }

  Future<void> _uploadBlockBlob({
    required String uploadUrl,
    required int fileSize,
    required int blockSize,
    required Future<Uint8List> Function(int start, int length) readRange,
    required String uploadId,
    required DateTime uploadStarted,
    required String contentType,
  }) async {
    final totalBlocks = (fileSize / blockSize).ceil();
    final blockIds = <String>[];
    int bytesSent = 0;

    for (int index = 0; index < totalBlocks; index++) {
      final start = index * blockSize;
      final length =
          (start + blockSize > fileSize) ? fileSize - start : blockSize;
      final blockId = _blockId(index);
      blockIds.add(blockId);
      final data = await readRange(start, length);

      final blockUri = _azureUri(uploadUrl, {
        'comp': 'block',
        'blockid': blockId,
      });

      for (int attempt = 0; attempt < maxRetriesPerBlock; attempt++) {
        try {
          final resp = await http
              .put(
                blockUri,
                headers: {
                  'Content-Length': data.length.toString(),
                  'Content-Type': 'application/octet-stream',
                },
                body: data,
              )
              .timeout(blockUploadTimeout);
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            bytesSent += length;
            _emit(uploadId, bytesSent, fileSize, 'uploading',
                started: uploadStarted);
            break;
          }
          if (attempt == maxRetriesPerBlock - 1) {
            throw Exception(
              'Azure block $index failed: HTTP ${resp.statusCode}',
            );
          }
        } on TimeoutException {
          if (attempt == maxRetriesPerBlock - 1) rethrow;
        }
        await Future<void>.delayed(Duration(seconds: 2 << attempt));
      }
    }

    final blockListXml = StringBuffer(
      '<?xml version="1.0" encoding="utf-8"?><BlockList>',
    );
    for (final id in blockIds) {
      blockListXml.write('<Latest>$id</Latest>');
    }
    blockListXml.write('</BlockList>');

    final listUri = _azureUri(uploadUrl, {'comp': 'blocklist'});
    final listResp = await http
        .put(
          listUri,
          headers: {
            'Content-Type': 'application/xml',
            'x-ms-blob-content-type': contentType,
          },
          body: blockListXml.toString(),
        )
        .timeout(blockUploadTimeout);

    if (listResp.statusCode < 200 || listResp.statusCode >= 300) {
      throw Exception(
        'Azure blocklist commit failed: HTTP ${listResp.statusCode}',
      );
    }
  }

  Uri _azureUri(String uploadUrl, Map<String, String> extra) {
    final uri = Uri.parse(uploadUrl);
    final qp = Map<String, String>.from(uri.queryParameters);
    qp.addAll(extra);
    return uri.replace(queryParameters: qp);
  }

  String _blockId(int index) {
    final padded = index.toString().padLeft(8, '0');
    return base64.encode(utf8.encode(padded));
  }

  void _emit(
    String uploadId,
    int bytesUploaded,
    int totalBytes,
    String stage, {
    DateTime? started,
  }) {
    final percent =
        totalBytes > 0 ? (bytesUploaded / totalBytes) * 100.0 : 0.0;
    Duration? eta;
    if (started != null && bytesUploaded > 0 && bytesUploaded < totalBytes) {
      final elapsed = DateTime.now().difference(started);
      final rate = bytesUploaded / elapsed.inMilliseconds;
      if (rate > 0) {
        final remainingMs = ((totalBytes - bytesUploaded) / rate).round();
        eta = Duration(milliseconds: remainingMs);
      }
    }
    onProgress?.call(BlobUploadProgress(
      uploadId: uploadId,
      bytesUploaded: bytesUploaded,
      totalBytes: totalBytes,
      percent: percent,
      stage: stage,
      estimatedRemaining: eta,
    ));
  }

  Future<void> _writeResumeId(String fileName, String uploadId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_kBlobResumeKeyPrefix$fileName', uploadId);
    } catch (_) {}
  }

  Future<void> _clearResumeId(String fileName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_kBlobResumeKeyPrefix$fileName');
    } catch (_) {}
  }

  static String _inferContentType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/pdf';
    }
  }
}
