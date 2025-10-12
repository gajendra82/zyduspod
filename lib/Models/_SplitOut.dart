import 'dart:io';

class SplitOut {
  final File file;
  final String? invoiceNo;
  final List<int>? pages;
  final int? sizeBytes;
  SplitOut({required this.file, this.invoiceNo, this.pages, this.sizeBytes});
}
