import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:printing/printing.dart';
import 'package:zxing2/zxing2.dart' as zxing;
import 'package:zxing2/qrcode.dart' as zxing_qr;

class EInvoiceQRExtractor {
  static Map<String, dynamic> decodeGstQr(String raw) {
    // Try raw JSON
    try {
      return jsonDecode(raw);
    } catch (_) {}

    // Try JWT-like base64url payload (middle part)
    try {
      if (raw.contains('.')) {
        final parts = raw.split('.');
        if (parts.length >= 2) {
          final payload = base64Url.normalize(parts[1]);
          final decoded = utf8.decode(base64Url.decode(payload));
          return jsonDecode(decoded);
        }
      }
    } catch (_) {}

    // Try plain base64
    try {
      final normalized = base64.normalize(raw);
      final decoded = utf8.decode(base64.decode(normalized));
      return jsonDecode(decoded);
    } catch (_) {}

    // Fallback: keep raw payload
    return {'raw': raw};
  }

  /// Rasterize first [maxPages] pages of [pdfFile] and try decoding a QR on each.
  /// Increase [dpi] to 320–360 if QRs are small; increase [maxPages] if needed.
  static Future<Map<String, dynamic>?> extractQRFromPDF(
    File pdfFile, {
    int maxPages = 3,
    double dpi = 300.0,
  }) async {
    try {
      final Uint8List data = await pdfFile.readAsBytes();
      final List<int> pagesToTry = List.generate(
        maxPages,
        (i) => i + 1,
      ); // 1-based

      await for (final raster in Printing.raster(
        data,
        dpi: dpi,
        pages: pagesToTry,
      )) {
        // Get raw RGBA bytes for the page
        final ui.Image uiImage = await raster.toImage();
        final byteData = await uiImage.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        uiImage.dispose();
        if (byteData == null) continue;

        final Uint8List rgba = byteData.buffer.asUint8List();
        final int width = raster.width;
        final int height = raster.height;
        final int pixelCount = width * height;
        if (rgba.length < pixelCount * 4) continue;

        // Convert RGBA (bytes) -> ARGB (Int32) for zxing2 RGBLuminanceSource
        final Int32List argb = _rgbaToArgb(rgba, pixelCount);

        // Try multiple strategies (binarizers, rotations, crops)
        final result = await _attemptDecodes(width, height, argb);
        if (result != null && result.isNotEmpty) {
          return decodeGstQr(result);
        }
      }
    } catch (_) {
      // ignore and return null
    }
    return null;
  }

  // ---------- Decoding strategies ----------

  static Future<String?> _attemptDecodes(
    int width,
    int height,
    Int32List argb,
  ) async {
    // 1) Original orientation: hybrid/global + BW
    for (final t in [
      _DecodeTask(mode: _Mode.hybrid, transform: _Transform.none),
      _DecodeTask(mode: _Mode.global, transform: _Transform.none),
      _DecodeTask(mode: _Mode.hybrid, transform: _Transform.bw),
    ]) {
      final text = _decodeWithTask(width, height, argb, t);
      if (text != null && text.isNotEmpty) return text;
    }

    // 2) Rotations: 90°, 270°
    final r90 = _rotate90(width, height, argb);
    for (final t in [
      _DecodeTask(mode: _Mode.hybrid, transform: _Transform.none),
      _DecodeTask(mode: _Mode.global, transform: _Transform.none),
      _DecodeTask(mode: _Mode.hybrid, transform: _Transform.bw),
    ]) {
      final text = _decodeWithTask(r90.$1, r90.$2, r90.$3, t);
      if (text != null && text.isNotEmpty) return text;
    }

    final r270 = _rotate270(width, height, argb);
    for (final t in [
      _DecodeTask(mode: _Mode.hybrid, transform: _Transform.none),
      _DecodeTask(mode: _Mode.global, transform: _Transform.none),
      _DecodeTask(mode: _Mode.hybrid, transform: _Transform.bw),
    ]) {
      final text = _decodeWithTask(r270.$1, r270.$2, r270.$3, t);
      if (text != null && text.isNotEmpty) return text;
    }

    // 3) Crops: center (80%, 60%), quadrants at 60%
    for (final crop in _generateCrops(width, height)) {
      final c = _cropARGB(
        width,
        height,
        argb,
        crop.$1,
        crop.$2,
        crop.$3,
        crop.$4,
      );
      for (final t in [
        _DecodeTask(mode: _Mode.hybrid, transform: _Transform.none),
        _DecodeTask(mode: _Mode.global, transform: _Transform.none),
        _DecodeTask(mode: _Mode.hybrid, transform: _Transform.bw),
      ]) {
        final text = _decodeWithTask(c.$1, c.$2, c.$3, t);
        if (text != null && text.isNotEmpty) return text;
      }
    }

    return null;
  }

  static String? _decodeWithTask(
    int width,
    int height,
    Int32List argb,
    _DecodeTask task,
  ) {
    try {
      final Int32List data = task.transform == _Transform.none
          ? argb
          : _toBWArgb(width, height, argb);

      final src = zxing.RGBLuminanceSource(width, height, data);
      final bin = task.mode == _Mode.hybrid
          ? zxing.HybridBinarizer(src)
          : zxing.GlobalHistogramBinarizer(src);
      final bitmap = zxing.BinaryBitmap(bin);

      final reader = zxing_qr.QRCodeReader();
      try {
        // No hints passed (compatible with zxing2 ^0.2.4 where setters aren't available)
        final res = reader.decode(bitmap);
        return res.text;
      } finally {
        reader.reset();
      }
    } catch (_) {
      return null;
    }
  }

  // ---------- Utilities ----------

  static Int32List _rgbaToArgb(Uint8List rgba, int pixelCount) {
    final Int32List out = Int32List(pixelCount);
    int si = 0;
    for (int i = 0; i < pixelCount; i++) {
      final int r = rgba[si];
      final int g = rgba[si + 1];
      final int b = rgba[si + 2];
      final int a = rgba[si + 3];
      si += 4;
      out[i] = (a << 24) | (r << 16) | (g << 8) | b;
    }
    return out;
  }

  // Convert to high-contrast black/white
  static Int32List _toBWArgb(
    int width,
    int height,
    Int32List argb, [
    int threshold = 140,
  ]) {
    final Int32List out = Int32List(argb.length);
    for (int i = 0; i < argb.length; i++) {
      final int c = argb[i];
      final int r = (c >> 16) & 0xFF;
      final int g = (c >> 8) & 0xFF;
      final int b = c & 0xFF;
      final int a = (c >> 24) & 0xFF;
      final int y = ((299 * r + 587 * g + 114 * b) / 1000).round();
      final int bw = (y > threshold) ? 0xFFFFFF : 0x000000;
      out[i] = (a << 24) | bw;
    }
    return out;
  }

  // Rotate 90° clockwise
  static (int, int, Int32List) _rotate90(
    int width,
    int height,
    Int32List argb,
  ) {
    final int w2 = height;
    final int h2 = width;
    final Int32List out = Int32List(argb.length);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int srcIdx = y * width + x;
        final int nx = height - 1 - y;
        final int ny = x;
        final int dstIdx = ny * w2 + nx;
        out[dstIdx] = argb[srcIdx];
      }
    }
    return (w2, h2, out);
  }

  // Rotate 270° clockwise (90° CCW)
  static (int, int, Int32List) _rotate270(
    int width,
    int height,
    Int32List argb,
  ) {
    final int w2 = height;
    final int h2 = width;
    final Int32List out = Int32List(argb.length);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int srcIdx = y * width + x;
        final int nx = y;
        final int ny = width - 1 - x;
        final int dstIdx = ny * w2 + nx;
        out[dstIdx] = argb[srcIdx];
      }
    }
    return (w2, h2, out);
  }

  // Crop rectangle: x, y, w, h
  static (int, int, Int32List) _cropARGB(
    int width,
    int height,
    Int32List argb,
    int x,
    int y,
    int w,
    int h,
  ) {
    final Int32List out = Int32List(w * h);
    int di = 0;
    for (int row = 0; row < h; row++) {
      final int srcRow = (y + row) * width;
      final int srcStart = srcRow + x;
      out.setRange(di, di + w, argb.sublist(srcStart, srcStart + w));
      di += w;
    }
    return (w, h, out);
  }

  // Generate crops: center 80%, center 60%, 4 quadrants @ 60%
  static List<(int, int, int, int)> _generateCrops(int width, int height) {
    final List<(int, int, int, int)> rects = [];

    final int c80w = (width * 0.8).round();
    final int c80h = (height * 0.8).round();
    final int c80x = ((width - c80w) / 2).round();
    final int c80y = ((height - c80h) / 2).round();
    rects.add((c80x, c80y, c80w, c80h));

    final int c60w = (width * 0.6).round();
    final int c60h = (height * 0.6).round();
    final int c60x = ((width - c60w) / 2).round();
    final int c60y = ((height - c60h) / 2).round();
    rects.add((c60x, c60y, c60w, c60h));

    // Quadrants at 60%
    final int qW = c60w;
    final int qH = c60h;
    rects.add((0, 0, qW, qH)); // top-left
    rects.add((width - qW, 0, qW, qH)); // top-right
    rects.add((0, height - qH, qW, qH)); // bottom-left
    rects.add((width - qW, height - qH, qW, qH)); // bottom-right

    // Clamp to bounds
    return rects.map((r) {
      int x = r.$1.clamp(0, width - 1);
      int y = r.$2.clamp(0, height - 1);
      int w = r.$3.clamp(1, width - x);
      int h = r.$4.clamp(1, height - y);
      return (x, y, w, h);
    }).toList();
  }
}

enum _Mode { hybrid, global }

enum _Transform { none, bw }

class _DecodeTask {
  final _Mode mode;
  final _Transform transform;
  _DecodeTask({required this.mode, required this.transform});
}
