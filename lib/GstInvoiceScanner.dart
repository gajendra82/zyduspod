import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zyduspod/config.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class GstQrApp extends StatelessWidget {
  final String podId;
  const GstQrApp({super.key, required this.podId});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "GST QR Scanner",
      theme: ThemeData(primarySwatch: Colors.teal),
      home: GstInvoiceScanner(podId: podId),
      debugShowCheckedModeBanner: false,
    );
  }
}

class GstInvoiceScanner extends StatefulWidget {
  final String podId;
  const GstInvoiceScanner({super.key, required this.podId});

  @override
  State<GstInvoiceScanner> createState() => _GstInvoiceScannerState();
}

class _GstInvoiceScannerState extends State<GstInvoiceScanner>
    with SingleTickerProviderStateMixin {
  bool isScanning = true;
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();
    _animController.dispose();
    super.dispose();
  }

  /// Decode GST QR with fallbacks
  Map<String, dynamic> decodeGstQr(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {}

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

    try {
      final normalized = base64.normalize(raw);
      final decoded = utf8.decode(base64.decode(normalized));
      return jsonDecode(decoded);
    } catch (_) {}

    return {"raw": raw};
  }

  void _onDetect(BarcodeCapture capture) {
    if (!isScanning) return;

    String? content;
    for (final barcode in capture.barcodes) {
      final candidate = barcode.rawValue ?? barcode.displayValue;
      if (candidate != null && candidate.isNotEmpty) {
        content = candidate.trim();
        break;
      }
    }

    if (content != null && content.isNotEmpty) {
      setState(() => isScanning = false);

      final decoded = decodeGstQr(content);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              InvoiceResultScreen(invoiceData: decoded, podId: widget.podId),
        ),
      ).then((_) {
        if (mounted) setState(() => isScanning = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const double boxSize = 260;

    return Scaffold(
      appBar: AppBar(title: const Text("GST E-Invoice QR Scanner")),
      body: Stack(
        children: [
          MobileScanner(controller: controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: boxSize,
              height: boxSize,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedBuilder(
                animation: _animController,
                builder: (context, child) {
                  double offsetY = _animController.value * (boxSize - 4);
                  return Stack(
                    children: [
                      Positioned(
                        top: offsetY,
                        left: 0,
                        right: 0,
                        child: Container(height: 2, color: Colors.red),
                      ),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          color: Colors.black54,
                          child: const Text(
                            "Align QR code here",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class InvoiceResultScreen extends StatefulWidget {
  final Map<String, dynamic> invoiceData;
  final String podId;
  const InvoiceResultScreen({
    super.key,
    required this.invoiceData,
    required this.podId,
  });

  @override
  State<InvoiceResultScreen> createState() => _InvoiceResultScreenState();
}

class _InvoiceResultScreenState extends State<InvoiceResultScreen> {
  late Map<String, dynamic> invoiceFields;
  bool loading = false;
  String? apiStatus;

  @override
  void initState() {
    super.initState();

    // unwrap "data" field if present
    final outer = widget.invoiceData;
    if (outer.containsKey("data") && outer["data"] is String) {
      try {
        invoiceFields = jsonDecode(outer["data"]);
      } catch (e) {
        invoiceFields = {"raw": outer["data"]};
      }
    } else {
      invoiceFields = outer;
    }
  }

  String _val(String key) {
    final v = invoiceFields[key];
    return (v != null && v.toString().isNotEmpty) ? v.toString() : "-";
  }

  Widget _infoTile(String title, String value, {Color? color}) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: ListTile(
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        subtitle: Text(value, style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  Future<void> sendToServer() async {
    setState(() {
      loading = true;
      apiStatus = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final uri = Uri.parse("${API_BASE_URL}pod/${widget.podId}/gst-verify");
      final headers = <String, String>{"Content-Type": "application/json"};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer ' + token;
      }

      final response = await http.post(
        uri,
        headers: headers,
        body: json.encode(invoiceFields),
      );

      if (response.statusCode == 200) {
        setState(() => apiStatus = "✅ Sent successfully!");
      } else {
        setState(
          () =>
              apiStatus = "❌ Error: ${response.statusCode} - ${response.body}",
        );
      }
    } catch (e) {
      setState(() => apiStatus = "❌ Exception: $e");
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("GST Invoice Details")),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Header card
          Card(
            color: Colors.teal.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Invoice No: ${_val("DocNo")}",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "Invoice Date: ${_val("DocDt")}",
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "IRN: ${_val("Irn")}",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    "IRN Date: ${_val("IrnDt")}",
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          _infoTile("Seller GSTIN", _val("SellerGstin"), color: Colors.teal),
          _infoTile("Buyer GSTIN", _val("BuyerGstin"), color: Colors.teal),

          _infoTile("Document Type", _val("DocTyp")),
          _infoTile("Total Invoice Value", _val("TotInvVal")),
          _infoTile("No. of Items", _val("ItemCnt")),
          _infoTile("Main HSN Code", _val("MainHsnCode")),

          if (apiStatus != null) ...[
            const SizedBox(height: 12),
            Text(
              apiStatus!,
              style: TextStyle(
                color: apiStatus!.contains("✅") ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: loading ? null : sendToServer,
        icon: loading
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.cloud_upload),
        label: const Text("Send to Server"),
      ),
    );
  }
}
