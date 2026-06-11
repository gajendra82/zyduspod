// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, RandomAccessFile;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zydus_vistaar/config.dart';

/// Server-side hard ceiling (kept in sync with PodChunkUploadController).
const int kChunkSizeBytes = 500 * 1024 * 1024; // 500 MB

/// SharedPreferences key prefix for resume bookkeeping.
/// Stores the most recent in-flight upload_id keyed by file name, so a
/// dropped connection / app crash can be resumed instead of restarting at
/// byte 0.
const String _kResumeKeyPrefix = 'pod_chunk_upload_resume_';

/// Progress snapshot emitted as the upload streams. All fields are best-effort
/// — `estimatedRemaining` is null until at least one chunk has completed.
class ChunkUploadProgress {
  final String uploadId;
  final int chunkIndex; // 1-based for UI ("Chunk 3 of 10")
  final int totalChunks;
  final int bytesUploaded;
  final int totalBytes;
  final double percent; // 0..100
  final Duration? estimatedRemaining;
  final String stage; // 'preparing' | 'uploading' | 'finalizing' | 'done'

  const ChunkUploadProgress({
    required this.uploadId,
    required this.chunkIndex,
    required this.totalChunks,
    required this.bytesUploaded,
    required this.totalBytes,
    required this.percent,
    required this.stage,
    this.estimatedRemaining,
  });
}

class ChunkUploadResult {
  final bool success;
  final int? podUploadBatchId;
  final String? batchId;
  final String? externalBatchId;
  final String? message;
  final String? error;
  final int statusCode;

  const ChunkUploadResult({
    required this.success,
    required this.statusCode,
    this.podUploadBatchId,
    this.batchId,
    this.externalBatchId,
    this.message,
    this.error,
  });

  factory ChunkUploadResult.fromJson(int statusCode, Map<String, dynamic> json) {
    return ChunkUploadResult(
      success: (json['success'] ?? false) == true,
      statusCode: statusCode,
      podUploadBatchId: json['pod_upload_batch_id'] is int
          ? json['pod_upload_batch_id'] as int
          : null,
      batchId: json['batch_id']?.toString(),
      externalBatchId: json['external_batch_id']?.toString(),
      message: json['message']?.toString(),
      error: json['error']?.toString(),
    );
  }
}

/// One-shot streamed chunked uploader.
///
/// Usage:
/// ```dart
/// final uploader = ChunkedUploader(
///   authToken: token,
///   context: {'stockist_id': '42'},
///   onProgress: (p) => print('${p.percent.toStringAsFixed(1)}%'),
/// );
/// final result = await uploader.upload(File('big.zip'));
/// ```
///
/// On Android / iOS / desktop, reads the file as a stream via
/// [RandomAccessFile] so RAM stays flat even for 5 GB files.
/// On web, [File] doesn't exist; pass the in-memory bytes via
/// [uploadBytes] instead (the picker already has them loaded).
class ChunkedUploader {
  final String authToken;
  final Map<String, String> context;
  final void Function(ChunkUploadProgress progress)? onProgress;
  final int chunkSize;
  final int maxRetriesPerChunk;
  final Duration chunkUploadTimeout;

  ChunkedUploader({
    required this.authToken,
    this.context = const {},
    this.onProgress,
    this.chunkSize = kChunkSizeBytes,
    this.maxRetriesPerChunk = 4,
    this.chunkUploadTimeout = const Duration(minutes: 15),
  });

  Uri get _chunkUri => Uri.parse('${API_BASE_URL}split-file-processor/chunk');
  Uri _sessionUri(String uid) =>
      Uri.parse('${API_BASE_URL}split-file-processor/session/$uid');

  /// Generate a v4-ish UUID using DateTime + random hex. Avoids pulling in
  /// the `uuid` package as a hard dependency — server-side validation
  /// accepts any string that fits Laravel's uuid rule pattern.
  String _generateUploadId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand1 = (now ^ 0x5A827999) & 0xFFFFFFFF;
    final rand2 = (now * 0x9E3779B9) & 0xFFFFFFFF;
    String hex(int v, int width) =>
        v.toRadixString(16).padLeft(width, '0').substring(0, width);
    return '${hex(now & 0xFFFFFFFF, 8)}-${hex(rand1 & 0xFFFF, 4)}-4${hex((rand2 >> 4) & 0xFFF, 3)}-${hex(((rand2 >> 16) & 0x3FFF) | 0x8000, 4)}-${hex(rand1, 8)}${hex(rand2 & 0xFFFF, 4)}';
  }

  Future<String?> _readResumeId(String fileName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_kResumeKeyPrefix$fileName');
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeResumeId(String fileName, String uploadId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_kResumeKeyPrefix$fileName', uploadId);
    } catch (_) {/* best effort */}
  }

  Future<void> _clearResumeId(String fileName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_kResumeKeyPrefix$fileName');
    } catch (_) {/* best effort */}
  }

  /// Mobile / desktop path: file lives on disk, stream-read it.
  Future<ChunkUploadResult> upload(File file) async {
    final fileName = file.path.split(RegExp(r'[/\\]')).last;
    final fileSize = await file.length();
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      return await _runUpload(
        fileName: fileName,
        fileSize: fileSize,
        readChunk: (int start, int length) async {
          await raf!.setPosition(start);
          return await raf.read(length);
        },
      );
    } finally {
      await raf?.close();
    }
  }

  /// Web path: bytes are already in memory (the picker loaded them);
  /// just slice on demand. Memory is the platform's choice, not ours.
  Future<ChunkUploadResult> uploadBytes({
    required String fileName,
    required Uint8List bytes,
  }) async {
    return _runUpload(
      fileName: fileName,
      fileSize: bytes.length,
      readChunk: (int start, int length) async {
        final end = (start + length).clamp(0, bytes.length);
        return Uint8List.fromList(bytes.sublist(start, end));
      },
    );
  }

  Future<ChunkUploadResult> _runUpload({
    required String fileName,
    required int fileSize,
    required Future<Uint8List> Function(int start, int length) readChunk,
  }) async {
    if (fileSize <= 0) {
      return const ChunkUploadResult(
        success: false,
        statusCode: 0,
        error: 'empty_file',
        message: 'File is empty.',
      );
    }
    final totalChunks = (fileSize / chunkSize).ceil();
    if (totalChunks > 200) {
      return ChunkUploadResult(
        success: false,
        statusCode: 0,
        error: 'too_many_chunks',
        message:
            'File would require $totalChunks chunks (max 200). Use a larger chunk size.',
      );
    }

    // Try to resume an existing session for this filename. If the server
    // has it and isn't completed yet, we'll skip indices it already has.
    String? uploadId = await _readResumeId(fileName);
    Set<int> alreadyHave = <int>{};
    if (uploadId != null) {
      try {
        final resp = await http.get(
          _sessionUri(uploadId),
          headers: {'Authorization': 'Bearer $authToken'},
        );
        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body);
          if (body is Map &&
              body['status'] == 'completed' &&
              body['pod_upload_batch_id'] != null) {
            // Already finished on a prior attempt — short-circuit.
            await _clearResumeId(fileName);
            return ChunkUploadResult.fromJson(
              resp.statusCode,
              body.cast<String, dynamic>(),
            );
          }
          if (body is Map &&
              (body['original_file_size'] == fileSize) &&
              (body['total_chunks'] == totalChunks)) {
            final received = (body['received_chunks'] as List?) ?? const [];
            alreadyHave = received.map((e) => (e as num).toInt()).toSet();
          } else {
            // Metadata changed (different file picked under same name) —
            // can't resume safely, start a fresh session.
            uploadId = null;
            alreadyHave = <int>{};
          }
        } else if (resp.statusCode == 404) {
          uploadId = null;
        }
      } catch (_) {
        // Resume probe failure shouldn't block the upload. Fall through
        // to a fresh upload_id below.
        uploadId = null;
      }
    }
    uploadId ??= _generateUploadId();
    await _writeResumeId(fileName, uploadId);

    _emit(
      uploadId: uploadId,
      chunkIndex: 0,
      totalChunks: totalChunks,
      bytesUploaded: 0,
      totalBytes: fileSize,
      stage: 'preparing',
      startedAt: DateTime.now(),
    );

    final startedAt = DateTime.now();
    int bytesUploadedSoFar = alreadyHave.fold<int>(0, (acc, _) => acc + chunkSize);
    if (bytesUploadedSoFar > fileSize) bytesUploadedSoFar = fileSize;

    ChunkUploadResult? lastResponse;

    for (int i = 0; i < totalChunks; i++) {
      if (alreadyHave.contains(i)) {
        continue;
      }
      final int startOffset = i * chunkSize;
      final int thisChunkSize = (i == totalChunks - 1)
          ? (fileSize - startOffset)
          : chunkSize;

      Uint8List chunkBytes;
      try {
        chunkBytes = await readChunk(startOffset, thisChunkSize);
      } catch (e) {
        return ChunkUploadResult(
          success: false,
          statusCode: 0,
          error: 'chunk_read_failed',
          message: 'Could not read chunk $i: $e',
        );
      }
      if (chunkBytes.length != thisChunkSize) {
        return ChunkUploadResult(
          success: false,
          statusCode: 0,
          error: 'chunk_short_read',
          message:
              'Chunk $i short-read: expected $thisChunkSize, got ${chunkBytes.length}.',
        );
      }

      ChunkUploadResult? attemptResult;
      Object? lastError;
      for (int attempt = 0; attempt < maxRetriesPerChunk; attempt++) {
        try {
          attemptResult = await _postChunk(
            uploadId: uploadId,
            chunkIndex: i,
            totalChunks: totalChunks,
            fileName: fileName,
            fileSize: fileSize,
            thisChunkSize: thisChunkSize,
            chunkBytes: chunkBytes,
          );
          if (attemptResult.success ||
              (attemptResult.statusCode >= 400 &&
                  attemptResult.statusCode < 500)) {
            // 4xx is non-retryable — break out so we surface the error.
            break;
          }
        } catch (e) {
          lastError = e;
        }
        // Exponential backoff: 2s, 4s, 8s, 16s — sleep before next attempt.
        if (attempt < maxRetriesPerChunk - 1) {
          await Future<void>.delayed(Duration(seconds: 2 << attempt));
        }
      }

      if (attemptResult == null) {
        return ChunkUploadResult(
          success: false,
          statusCode: 0,
          error: 'chunk_upload_exhausted',
          message:
              'Chunk $i failed after $maxRetriesPerChunk attempts: $lastError',
        );
      }
      if (!attemptResult.success && i < totalChunks - 1) {
        return attemptResult;
      }
      lastResponse = attemptResult;
      bytesUploadedSoFar += thisChunkSize;

      _emit(
        uploadId: uploadId,
        chunkIndex: i + 1,
        totalChunks: totalChunks,
        bytesUploaded: bytesUploadedSoFar,
        totalBytes: fileSize,
        stage: (i == totalChunks - 1) ? 'finalizing' : 'uploading',
        startedAt: startedAt,
      );
    }

    // Server auto-finalizes on the last chunk, so lastResponse should
    // contain the final batch info. Clear the resume bookmark.
    await _clearResumeId(fileName);

    _emit(
      uploadId: uploadId,
      chunkIndex: totalChunks,
      totalChunks: totalChunks,
      bytesUploaded: fileSize,
      totalBytes: fileSize,
      stage: 'done',
      startedAt: startedAt,
    );

    return lastResponse ??
        const ChunkUploadResult(
          success: false,
          statusCode: 0,
          error: 'no_response',
          message: 'Upload finished but no server response was captured.',
        );
  }

  Future<ChunkUploadResult> _postChunk({
    required String uploadId,
    required int chunkIndex,
    required int totalChunks,
    required String fileName,
    required int fileSize,
    required int thisChunkSize,
    required Uint8List chunkBytes,
  }) async {
    final req = http.MultipartRequest('POST', _chunkUri);
    req.headers['Authorization'] = 'Bearer $authToken';
    req.headers['Connection'] = 'close';
    req.fields['upload_id'] = uploadId;
    req.fields['chunk_index'] = chunkIndex.toString();
    req.fields['total_chunks'] = totalChunks.toString();
    req.fields['original_file_name'] = fileName;
    req.fields['original_file_size'] = fileSize.toString();
    req.fields['chunk_size'] = thisChunkSize.toString();
    context.forEach((k, v) {
      req.fields[k] = v;
    });
    req.files.add(http.MultipartFile.fromBytes(
      'chunk',
      chunkBytes,
      filename: 'chunk_$chunkIndex',
      contentType: MediaType('application', 'octet-stream'),
    ));

    final streamed = await req.send().timeout(chunkUploadTimeout);
    final body = await http.Response.fromStream(streamed);
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(body.body);
      json = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'raw': decoded};
    } catch (_) {
      json = <String, dynamic>{
        'success': false,
        'message': 'Non-JSON response: HTTP ${body.statusCode}',
        'error': 'invalid_json_response',
      };
    }
    return ChunkUploadResult.fromJson(body.statusCode, json);
  }

  void _emit({
    required String uploadId,
    required int chunkIndex,
    required int totalChunks,
    required int bytesUploaded,
    required int totalBytes,
    required String stage,
    required DateTime startedAt,
  }) {
    final cb = onProgress;
    if (cb == null) return;
    final pct = totalBytes <= 0
        ? 0.0
        : (bytesUploaded * 100.0 / totalBytes).clamp(0.0, 100.0);

    Duration? eta;
    if (stage == 'uploading' && bytesUploaded > 0) {
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      if (elapsedMs > 0) {
        final bytesPerMs = bytesUploaded / elapsedMs;
        if (bytesPerMs > 0) {
          final remainingBytes = (totalBytes - bytesUploaded).clamp(0, totalBytes);
          eta = Duration(milliseconds: (remainingBytes / bytesPerMs).round());
        }
      }
    }

    cb(ChunkUploadProgress(
      uploadId: uploadId,
      chunkIndex: chunkIndex,
      totalChunks: totalChunks,
      bytesUploaded: bytesUploaded,
      totalBytes: totalBytes,
      percent: pct,
      stage: stage,
      estimatedRemaining: eta,
    ));
  }
}
