import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zydus_vistaar/services/BlobDirectUploader.dart';
import 'package:zydus_vistaar/services/PodZipExpander.dart';

/// Lightweight singleton that keeps Azure uploads running while the user
/// navigates to the status/dashboard screens.
///
/// Note: this is "background" in the UX sense (non-blocking UI). On Flutter Web
/// the browser may pause/cancel in-flight requests if the tab is closed.
class PodBackgroundUploadManager {
  PodBackgroundUploadManager._();

  static final PodBackgroundUploadManager instance = PodBackgroundUploadManager._();

  final ValueNotifier<PodBackgroundUploadState?> state = ValueNotifier(null);

  bool get isRunning => state.value?.isRunning == true;

  Future<void> start({
    required List<PodUploadItem> items,
    required String stockistId,
    required String authToken,
  }) async {
    // If a run is already active, keep it (status screen will attach).
    if (isRunning) return;

    final uploadId = _newUploadId();
    state.value = PodBackgroundUploadState(
      uploadId: uploadId,
      stage: PodUploadStage.preparing,
      currentFileIndex: 0,
      totalFiles: items.length,
      currentFileName: items.isNotEmpty ? items.first.fileName : null,
      percent: 0,
      message: 'Preparing cloud upload…',
      isRunning: true,
    );

    try {
      int? lastBatchDbId;
      String? lastExternalBatchId;

      final Map<String, dynamic> baseContext = {
        'stockist_id': int.tryParse(stockistId) ?? stockistId,
      };

      for (int i = 0; i < items.length; i++) {
        final item = items[i];

        void onProgress(BlobUploadProgress p) {
          final msg = switch (p.stage) {
            'preparing' => 'Preparing Azure upload…',
            'uploading' => 'Uploading to cloud storage…',
            'finalizing' => 'Finalizing on server…',
            'done' => 'Completed.',
            _ => 'Uploading…',
          };
          state.value = state.value?.copyWith(
            stage: _mapStage(p.stage),
            currentFileIndex: i + 1,
            totalFiles: items.length,
            currentFileName: item.fileName,
            percent: p.stage == 'finalizing' ? null : p.percent.round(),
            message: msg,
          );
        }

        final uploader = BlobDirectUploader(
          authToken: authToken,
          context: baseContext,
          onProgress: onProgress,
        );

        final BlobUploadResult result;
        if (item.file != null) {
          result = await uploader.upload(item.file!);
        } else if (item.bytes != null) {
          result = await uploader.uploadBytes(
            fileName: item.fileName,
            bytes: item.bytes!,
          );
        } else {
          continue;
        }

        if (!result.success) {
          state.value = state.value?.copyWith(
            isRunning: false,
            errorMessage: result.message ?? result.error ?? 'Upload failed.',
          );
          return;
        }

        lastBatchDbId = result.podUploadBatchId;
        lastExternalBatchId = result.externalBatchId ?? result.batchId;
      }

      state.value = state.value?.copyWith(
        isRunning: false,
        stage: PodUploadStage.done,
        percent: 100,
        message: 'Upload complete. Processing on server…',
        podUploadBatchId: lastBatchDbId,
        externalBatchId: lastExternalBatchId,
      );
    } catch (e) {
      state.value = state.value?.copyWith(
        isRunning: false,
        errorMessage: e.toString(),
      );
    }
  }

  PodUploadStage _mapStage(String stage) {
    return switch (stage) {
      'preparing' => PodUploadStage.preparing,
      'uploading' => PodUploadStage.uploading,
      'finalizing' => PodUploadStage.finalizing,
      'done' => PodUploadStage.done,
      _ => PodUploadStage.uploading,
    };
  }

  String _newUploadId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'pod_bg_$now';
  }
}

enum PodUploadStage { preparing, uploading, finalizing, done }

@immutable
class PodBackgroundUploadState {
  final String uploadId;
  final PodUploadStage stage;
  final int currentFileIndex; // 1-based for display
  final int totalFiles;
  final String? currentFileName;
  final int? percent; // null when unknown
  final String message;

  final bool isRunning;
  final String? errorMessage;
  final int? podUploadBatchId;
  final String? externalBatchId;

  const PodBackgroundUploadState({
    required this.uploadId,
    required this.stage,
    required this.currentFileIndex,
    required this.totalFiles,
    required this.currentFileName,
    required this.percent,
    required this.message,
    required this.isRunning,
    this.errorMessage,
    this.podUploadBatchId,
    this.externalBatchId,
  });

  PodBackgroundUploadState copyWith({
    PodUploadStage? stage,
    int? currentFileIndex,
    int? totalFiles,
    String? currentFileName,
    int? percent,
    String? message,
    bool? isRunning,
    String? errorMessage,
    int? podUploadBatchId,
    String? externalBatchId,
  }) {
    return PodBackgroundUploadState(
      uploadId: uploadId,
      stage: stage ?? this.stage,
      currentFileIndex: currentFileIndex ?? this.currentFileIndex,
      totalFiles: totalFiles ?? this.totalFiles,
      currentFileName: currentFileName ?? this.currentFileName,
      percent: percent,
      message: message ?? this.message,
      isRunning: isRunning ?? this.isRunning,
      errorMessage: errorMessage ?? this.errorMessage,
      podUploadBatchId: podUploadBatchId ?? this.podUploadBatchId,
      externalBatchId: externalBatchId ?? this.externalBatchId,
    );
  }
}

