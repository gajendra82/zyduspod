import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zyduspod/config.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// class GstQrApp extends StatelessWidget {
//   final String podId;
//   const GstQrApp({super.key, required this.podId});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: "GST QR Scanner",
//       theme: ThemeData(primarySwatch: Colors.teal),
//       home: GstInvoiceScanner(podId: podId),
//       debugShowCheckedModeBanner: false,
//     );
//   }
// }

class GstQrApp extends StatefulWidget {
  final String podId;
  const GstQrApp({super.key, required this.podId});

  @override
  State<GstQrApp> createState() => _GstQrAppState();
}

class _GstQrAppState extends State<GstQrApp>
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

  void _onDetect(BarcodeCapture capture) async{
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

      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (_) => InvoiceResultScreen(
                invoiceData: decoded,
                podId: widget.podId,
              ),
        ),
      ).then((_) {
        if (mounted) setState(() => isScanning = true);
      });
      setState(() => isScanning = true);
      print('Decoded: $decoded');

    }
  }

  @override
  Widget build(BuildContext context) {
    const double boxSize = 260;

    return Scaffold(
      appBar: AppBar(
        title: const Text("GST E-Invoice QR Scanner"),
        leading: IconButton(
          onPressed: () {
            Navigator.pop(context);
          },
          icon: Icon(Icons.arrow_back),
        ),
      ),
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

  Widget _buildInfoCard(String title, String value, IconData icon, {Color? color}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            Colors.grey.shade50,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (color ?? const Color(0xFF00A0A8)).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: color ?? const Color(0xFF00A0A8),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          "GST Invoice Details",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF00A0A8),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card with gradient
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00A0A8), Color(0xFF00C4CC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00A0A8).withOpacity(0.3),
                    spreadRadius: 2,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.receipt_long,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Invoice Number",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                _val("DocNo"),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Invoice Date",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                _val("DocDt"),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "IRN Date",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                _val("IrnDt"),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "IRN",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _val("Irn"),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Section title
            const Text(
              "Invoice Details",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),

            // Info cards
            _buildInfoCard("Seller GSTIN", _val("SellerGstin"), Icons.business, color: const Color(0xFF00A0A8)),
            _buildInfoCard("Buyer GSTIN", _val("BuyerGstin"), Icons.account_balance, color: const Color(0xFF00A0A8)),
            _buildInfoCard("Document Type", _val("DocTyp"), Icons.description, color: Colors.orange),
            _buildInfoCard("Total Invoice Value", _val("TotInvVal"), Icons.currency_rupee, color: Colors.green),
            _buildInfoCard("No. of Items", _val("ItemCnt"), Icons.inventory, color: Colors.blue),
            _buildInfoCard("Main HSN Code", _val("MainHsnCode"), Icons.qr_code, color: Colors.purple),

            const SizedBox(height: 24),

            // Status message
            if (apiStatus != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: apiStatus!.contains("✅") ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: apiStatus!.contains("✅") ? Colors.green.shade200 : Colors.red.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      apiStatus!.contains("✅") ? Icons.check_circle : Icons.error,
                      color: apiStatus!.contains("✅") ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        apiStatus!,
                        style: TextStyle(
                          color: apiStatus!.contains("✅") ? Colors.green.shade700 : Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Send button
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00A0A8), Color(0xFF00C4CC)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00A0A8).withOpacity(0.3),
                    spreadRadius: 1,
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: loading ? null : sendToServer,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (loading)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        else
                          const Icon(
                            Icons.cloud_upload_outlined,
                            color: Colors.white,
                            size: 24,
                          ),
                        const SizedBox(width: 12),
                        Text(
                          loading ? "Sending..." : "Send to Server",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
