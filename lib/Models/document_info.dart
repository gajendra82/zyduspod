import 'dart:io';
import 'dart:typed_data';

/// Status of QR processing for a document
enum QRProcessingStatus {
  pending,
  processing,
  completed,
  failed,
}

/// Model class to hold document information with independent byte copies
/// to prevent PDF preview issues when multiple documents are uploaded.
class DocumentInfo {
  final File? file;
  final Uint8List? webBytes;
  final String displayName;
  final bool isValid;
  final Map<String, dynamic>? qrData;
  final QRProcessingStatus qrStatus;
  final bool isGoodForExtraction;
  final double ocrConfidence;
  final String qualityMessage;

  DocumentInfo({
    this.file,
    this.webBytes,
    required this.displayName,
    required this.isValid,
    this.qrData,
    required this.qrStatus,
    required this.isGoodForExtraction,
    required this.ocrConfidence,
    required this.qualityMessage,
  });

  /// Creates a copy of this DocumentInfo with optional overrides.
  DocumentInfo copyWith({
    File? file,
    Uint8List? webBytes,
    String? displayName,
    bool? isValid,
    Map<String, dynamic>? qrData,
    QRProcessingStatus? qrStatus,
    bool? isGoodForExtraction,
    double? ocrConfidence,
    String? qualityMessage,
  }) {
    return DocumentInfo(
      file: file ?? this.file,
      webBytes: webBytes ?? this.webBytes,
      displayName: displayName ?? this.displayName,
      isValid: isValid ?? this.isValid,
      qrData: qrData ?? this.qrData,
      qrStatus: qrStatus ?? this.qrStatus,
      isGoodForExtraction: isGoodForExtraction ?? this.isGoodForExtraction,
      ocrConfidence: ocrConfidence ?? this.ocrConfidence,
      qualityMessage: qualityMessage ?? this.qualityMessage,
    );
  }

  /// Returns the bytes of this document.
  /// Priority: webBytes (independent copy) > file bytes
  Future<Uint8List?> getBytes() async {
    if (webBytes != null) {
      return webBytes;
    }
    if (file != null && await file!.exists()) {
      return await file!.readAsBytes();
    }
    return null;
  }
}

/// Result from PDF splitting operation
class SplitPdfPart {
  final Uint8List bytes;
  final String? invoiceNo;

  SplitPdfPart({required this.bytes, this.invoiceNo});
}
