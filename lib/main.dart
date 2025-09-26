import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
// import 'package:zyduspod/GstInvoiceScanner.dart';
import 'package:zyduspod/DocumentUploadScreen.dart';
import 'package:zyduspod/login_screen.dart';
import 'package:zyduspod/screens/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<Widget> _determineStartScreen() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    if (token != null && token.isNotEmpty) {
      return const DocumentUploadScreen();
    }
    return const LoginScreen();
  }

  @override
  Widget build(BuildContext context) {
    final Color brandTeal = const Color(0xFF00A0A8);
    final Color brandMagenta = const Color(0xFFB24B9E);
    final Color brandAccent = const Color(0xFF6EC1C7);

    return MaterialApp(
      title: 'Zydus Vistaar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: brandTeal,
          primary: brandTeal,
          secondary: brandMagenta,
          tertiary: brandAccent,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF00A0A8),
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: brandTeal,
            foregroundColor: Colors.white,
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(filled: true),
        useMaterial3: true,
      ),
      home: FutureBuilder<Widget>(
        future: _determineStartScreen(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return snapshot.data!;
        },
      ),
    );
  }
}

class GstQrScannerPage extends StatefulWidget {
  const GstQrScannerPage({Key? key}) : super(key: key);

  @override
  State<GstQrScannerPage> createState() => _GstQrScannerPageState();
}

class _GstQrScannerPageState extends State<GstQrScannerPage> {
  String? scannedData;
  Map<String, dynamic>? invoiceDetails;
  bool isScanning = true;

  void _processQrData(String rawData) {
    try {
      // The GST QR code is usually Base64 or JWT
      String decoded = _tryDecodeJwtOrBase64(rawData);

      // Now try to parse JSON
      Map<String, dynamic> jsonMap = jsonDecode(decoded);
      setState(() {
        scannedData = rawData;
        invoiceDetails = jsonMap;
        isScanning = false;
      });
    } catch (e) {
      setState(() {
        scannedData = "Decoding failed: $e";
        invoiceDetails = null;
        isScanning = false;
      });
    }
  }

  String _tryDecodeJwtOrBase64(String data) {
    // If JWT-like: header.payload.signature
    if (data.contains('.')) {
      final parts = data.split('.');
      if (parts.length >= 2) {
        return utf8.decode(base64Url.decode(_normalizeBase64(parts[1])));
      }
    }
    // Else treat as base64
    return utf8.decode(base64.decode(_normalizeBase64(data)));
  }

  String _normalizeBase64(String input) {
    // Fix missing padding
    int padding = input.length % 4;
    if (padding > 0) {
      input += '=' * (4 - padding);
    }
    return input.replaceAll('-', '+').replaceAll('_', '/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("GST E-Invoice QR Scanner")),
      body: isScanning
          ? MobileScanner(
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  final String? code = barcode.rawValue;
                  if (code != null) {
                    _processQrData(code);
                    break;
                  }
                }
              },
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: invoiceDetails != null
                  ? ListView(
                      children: invoiceDetails!.entries
                          .map(
                            (e) => ListTile(
                              title: Text(e.key),
                              subtitle: Text(e.value.toString()),
                            ),
                          )
                          .toList(),
                    )
                  : Text(scannedData ?? "No data"),
            ),
      floatingActionButton: !isScanning
          ? FloatingActionButton(
              onPressed: () {
                setState(() {
                  isScanning = true;
                  scannedData = null;
                  invoiceDetails = null;
                });
              },
              child: const Icon(Icons.qr_code_scanner),
            )
          : null,
    );
  }
}
