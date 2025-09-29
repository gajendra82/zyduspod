import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
// import 'package:zyduspod/GstInvoiceScanner.dart';
import 'package:zyduspod/screens/splash_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Removed _determineStartScreen as splash screen now handles navigation

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
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF2C3E50),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Color(0xFF2C3E50),
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: brandTeal,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF00A0A8), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: Colors.white,
        ),
        useMaterial3: true,
        fontFamily: 'SF Pro Display',
      ),
      home: const SplashScreen(),
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
