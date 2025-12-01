import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class WebCameraHelper {
  static final WebCameraHelper _instance = WebCameraHelper._internal();
  factory WebCameraHelper() => _instance;
  WebCameraHelper._internal();

  Completer<Uint8List?>? _cameraCompleter;
  Completer<List<CapturedImage>>? _galleryCompleter;

  /// Capture single image from camera
  Future<Uint8List?> captureFromCamera() async {
    if (!kIsWeb) {
      throw UnsupportedError('This method is only for web');
    }

    _cameraCompleter = Completer<Uint8List?>();

    // Set up event listeners
    late html.EventListener capturedListener;
    late html.EventListener cancelledListener;

    capturedListener = (html.Event event) {
      final customEvent = event as html.CustomEvent;
      final detail = customEvent.detail;

      if (detail != null && detail['base64'] != null) {
        final base64String = detail['base64'] as String;
        final bytes = base64Decode(base64String);
        _cameraCompleter?.complete(bytes);
      } else {
        _cameraCompleter?.complete(null);
      }

      // Clean up listeners
      html.window.removeEventListener(
        'camera_image_captured',
        capturedListener,
      );
      html.window.removeEventListener(
        'camera_capture_cancelled',
        cancelledListener,
      );
    };

    cancelledListener = (html.Event event) {
      _cameraCompleter?.complete(null);

      // Clean up listeners
      html.window.removeEventListener(
        'camera_image_captured',
        capturedListener,
      );
      html.window.removeEventListener(
        'camera_capture_cancelled',
        cancelledListener,
      );
    };

    html.window.addEventListener('camera_image_captured', capturedListener);
    html.window.addEventListener('camera_capture_cancelled', cancelledListener);

    // Trigger camera capture using dart:js
    try {
      // Check if function exists and call it
      if (js.context.hasProperty('triggerCameraCapture')) {
        js.context.callMethod('triggerCameraCapture');
      } else {
        debugPrint('triggerCameraCapture function not found');
        _cameraCompleter?.complete(null);
      }
    } catch (e) {
      debugPrint('Error triggering camera: $e');
      _cameraCompleter?.complete(null);
    }

    return _cameraCompleter!.future;
  }

  /// Pick multiple images from gallery
  Future<List<CapturedImage>> pickFromGallery() async {
    if (!kIsWeb) {
      throw UnsupportedError('This method is only for web');
    }

    _galleryCompleter = Completer<List<CapturedImage>>();

    late html.EventListener selectedListener;
    late html.EventListener cancelledListener;

    selectedListener = (html.Event event) {
      final customEvent = event as html.CustomEvent;
      final detail = customEvent.detail;

      if (detail != null && detail['images'] != null) {
        final imagesList = detail['images'] as List;
        final capturedImages =
            imagesList.map((img) {
              final base64String = img['base64'] as String;
              final bytes = base64Decode(base64String);
              return CapturedImage(
                bytes: bytes,
                filename: img['filename'] as String? ?? 'image.jpg',
              );
            }).toList();

        _galleryCompleter?.complete(capturedImages);
      } else {
        _galleryCompleter?.complete([]);
      }

      // Clean up listeners
      html.window.removeEventListener(
        'gallery_images_selected',
        selectedListener,
      );
      html.window.removeEventListener(
        'gallery_selection_cancelled',
        cancelledListener,
      );
    };

    cancelledListener = (html.Event event) {
      _galleryCompleter?.complete([]);

      // Clean up listeners
      html.window.removeEventListener(
        'gallery_images_selected',
        selectedListener,
      );
      html.window.removeEventListener(
        'gallery_selection_cancelled',
        cancelledListener,
      );
    };

    html.window.addEventListener('gallery_images_selected', selectedListener);
    html.window.addEventListener(
      'gallery_selection_cancelled',
      cancelledListener,
    );

    // Trigger gallery picker using dart:js
    try {
      // Check if function exists and call it
      if (js.context.hasProperty('triggerGalleryPicker')) {
        js.context.callMethod('triggerGalleryPicker');
      } else {
        debugPrint('triggerGalleryPicker function not found');
        _galleryCompleter?.complete([]);
      }
    } catch (e) {
      debugPrint('Error triggering gallery: $e');
      _galleryCompleter?.complete([]);
    }

    return _galleryCompleter!.future;
  }
}

class CapturedImage {
  final Uint8List bytes;
  final String filename;

  CapturedImage({required this.bytes, required this.filename});
}
