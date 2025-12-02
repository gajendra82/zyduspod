import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:async';

class WebCameraHelper {
  Future<Uint8List?> captureFromCamera() async {
    try {
      // Check if running on HTTPS or localhost
      final protocol = html.window.location.protocol;
      final hostname = html.window.location.hostname;

      if (protocol != 'https:' &&
          !(hostname?.contains('localhost') ?? false) &&
          !(hostname?.contains('127.0.0.1') ?? false)) {
        throw Exception(
          'Camera access requires HTTPS. Please access the site via https:// or localhost',
        );
      }

      // Check if mediaDevices is supported
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        throw Exception('MediaDevices not supported in this browser');
      }

      // Request camera with mobile-friendly constraints
      final constraints = {
        'video': {
          'facingMode': 'environment', // Use back camera on mobile
          'width': {'ideal': 1920},
          'height': {'ideal': 1080},
        },
        'audio': false,
      };

      html.MediaStream? stream;
      try {
        stream = await mediaDevices.getUserMedia(constraints);
      } catch (e) {
        // Fallback to simpler constraints if the above fails
        stream = await mediaDevices.getUserMedia({
          'video': true,
          'audio': false,
        });
      }

      // Create a container for the video preview
      final container =
          html.DivElement()
            ..style.position = 'fixed'
            ..style.top = '0'
            ..style.left = '0'
            ..style.width = '100vw'
            ..style.height = '100vh'
            ..style.backgroundColor = 'black'
            ..style.zIndex = '9999'
            ..style.display = 'flex'
            ..style.flexDirection = 'column'
            ..style.justifyContent = 'center'
            ..style.alignItems = 'center';

      // Create video element
      final video =
          html.VideoElement()
            ..srcObject = stream
            ..autoplay = true
            ..setAttribute('playsinline', 'true') // Important for iOS/mobile
            ..style.width = '100%'
            ..style.height = 'auto'
            ..style.maxHeight = '80vh'
            ..style.objectFit = 'contain';

      // Create capture button
      final captureButton =
          html.ButtonElement()
            ..text = '📸 Capture'
            ..style.position = 'absolute'
            ..style.bottom = '80px'
            ..style.padding = '15px 40px'
            ..style.fontSize = '18px'
            ..style.backgroundColor = '#00A0A8'
            ..style.color = 'white'
            ..style.border = 'none'
            ..style.borderRadius = '30px'
            ..style.cursor = 'pointer'
            ..style.zIndex = '10000';

      // Create cancel button
      final cancelButton =
          html.ButtonElement()
            ..text = '✖ Cancel'
            ..style.position = 'absolute'
            ..style.bottom = '20px'
            ..style.padding = '10px 30px'
            ..style.fontSize = '16px'
            ..style.backgroundColor = '#ff4444'
            ..style.color = 'white'
            ..style.border = 'none'
            ..style.borderRadius = '20px'
            ..style.cursor = 'pointer'
            ..style.zIndex = '10000';

      container.children.addAll([video, captureButton, cancelButton]);
      html.document.body?.append(container);

      // Wait for video to be ready
      await video.onLoadedMetadata.first;

      // Give time for camera to initialize
      await Future.delayed(const Duration(milliseconds: 500));

      // Create completer for user action
      final completer = Completer<Uint8List?>();

      // Capture button click handler
      captureButton.onClick.listen((_) async {
        try {
          // Create canvas with video dimensions
          final canvas = html.CanvasElement(
            width: video.videoWidth,
            height: video.videoHeight,
          );

          // Draw video frame to canvas
          final context = canvas.context2D;
          context.drawImageScaled(video, 0, 0, canvas.width!, canvas.height!);

          // Convert to JPEG bytes
          final dataUrl = canvas.toDataUrl('image/jpeg', 0.92);
          final base64Data = dataUrl.split(',')[1];

          // Decode base64
          final bytes = html.window.atob(base64Data);
          final uint8List = Uint8List.fromList(
            List<int>.generate(bytes.length, (i) => bytes.codeUnitAt(i)),
          );

          // Stop all tracks
          stream?.getTracks().forEach((track) => track.stop());

          // Remove UI
          container.remove();

          completer.complete(uint8List);
        } catch (e) {
          print('[Camera] Capture error: $e');
          stream?.getTracks().forEach((track) => track.stop());
          container.remove();
          completer.completeError(e);
        }
      });

      // Cancel button click handler
      cancelButton.onClick.listen((_) {
        stream?.getTracks().forEach((track) => track.stop());
        container.remove();
        completer.complete(null);
      });

      return await completer.future;
    } catch (e) {
      print('[Camera] Error: $e');
      rethrow;
    }
  }

  Future<List<WebImage>> pickFromGallery() async {
    try {
      final uploadInput =
          html.FileUploadInputElement()
            ..accept = 'image/*'
            ..multiple = true;

      uploadInput.click();

      // Wait for user to select files
      await uploadInput.onChange.first;

      final files = uploadInput.files;
      if (files == null || files.isEmpty) {
        return [];
      }

      final List<WebImage> images = [];

      for (final file in files) {
        final reader = html.FileReader();
        reader.readAsArrayBuffer(file);
        await reader.onLoad.first;

        final bytes = reader.result as Uint8List;
        images.add(WebImage(bytes: bytes, filename: file.name));
      }

      return images;
    } catch (e) {
      print('[Gallery] Error: $e');
      return [];
    }
  }
}

class WebImage {
  final Uint8List bytes;
  final String filename;

  WebImage({required this.bytes, required this.filename});
}
