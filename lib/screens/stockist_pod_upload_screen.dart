import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, SocketException;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zydus_vistaar/config.dart';
import 'package:zydus_vistaar/routes.dart';
import 'package:zydus_vistaar/services/ChunkedUploader.dart';
import 'package:zydus_vistaar/widgets/modern_ui_components.dart';

/// Dedicated POD upload screen for stockist logins.
///
/// Differences from the KAM screen:
///  - the stockist is auto-resolved from the logged-in user (no picker)
///  - hospital is optional (search-as-you-type from the stockist's set)
///  - one or more invoices may be picked (also optional, scoped to the
///    selected hospital when present)
///  - PDFs go through the same split + extract pipeline as KAM uploads
class StockistPodUploadScreen extends StatefulWidget {
  const StockistPodUploadScreen({super.key});

  @override
  State<StockistPodUploadScreen> createState() => _StockistPodUploadScreenState();
}

class _StockistPodUploadScreenState extends State<StockistPodUploadScreen> {
  // Stockist context — read from SharedPreferences set at login time.
  int? _stockistId;
  String? _stockistName;
  String? _stockistCode;

  // Optional selections.
  _HospitalOption? _selectedHospital;
  final Set<int> _selectedInvoiceIds = {};
  final Map<int, _InvoiceOption> _invoiceById = {};

  // Async state.
  bool _loadingHospitals = false;
  bool _loadingInvoices = false;
  bool _uploading = false;

  // Picked files.
  final List<_PickedFile> _files = [];

  // Cached lookups (for the popup search dialogs).
  List<_HospitalOption> _hospitalCache = const [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _stockistId = prefs.getInt('stockistId');
      _stockistName = prefs.getString('stockistName');
      _stockistCode = prefs.getString('stockistCode');
    });
    if (_stockistId == null || _stockistId == 0) {
      // Logged-in user isn't a stockist — bounce them back to the normal app.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.mainNavigation,
          (route) => false,
        );
      });
      return;
    }
    await _loadHospitals();
  }

  Future<String?> _authToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken');
  }

  // ── Hospital dropdown ─────────────────────────────────────────────────
  Future<void> _loadHospitals({String q = ''}) async {
    setState(() => _loadingHospitals = true);
    try {
      final token = await _authToken();
      final uri = Uri.parse(
        '${API_BASE_URL}stockist/hospitals?limit=100${q.isNotEmpty ? '&q=${Uri.encodeQueryComponent(q)}' : ''}',
      );
      final resp = await http.get(uri, headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final rows = (body['data'] as List?) ?? [];
      _hospitalCache = rows
          .whereType<Map<String, dynamic>>()
          .map(_HospitalOption.fromJson)
          .toList();
      if (mounted) setState(() {});
    } catch (_) {
      // Silent: dropdown will simply be empty.
    } finally {
      if (mounted) setState(() => _loadingHospitals = false);
    }
  }

  Future<void> _openHospitalPicker() async {
    final picked = await showDialog<_HospitalOption?>(
      context: context,
      builder: (_) => _HospitalPickerDialog(
        initial: _hospitalCache,
        onSearch: (q) async {
          await _loadHospitals(q: q);
          return _hospitalCache;
        },
      ),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _selectedHospital = picked;
        _selectedInvoiceIds.clear();
        _invoiceById.clear();
      });
      _loadInvoices(hospitalId: picked.id);
    }
  }

  void _clearHospital() {
    setState(() {
      _selectedHospital = null;
      _selectedInvoiceIds.clear();
      _invoiceById.clear();
    });
  }

  // ── Invoice selector ──────────────────────────────────────────────────
  Future<void> _loadInvoices({int? hospitalId, String q = ''}) async {
    setState(() => _loadingInvoices = true);
    try {
      final token = await _authToken();
      final params = <String>[
        'limit=200',
        if (hospitalId != null) 'hospital_id=$hospitalId',
        if (q.isNotEmpty) 'q=${Uri.encodeQueryComponent(q)}',
      ];
      final uri = Uri.parse('${API_BASE_URL}stockist/invoices?${params.join('&')}');
      final resp = await http.get(uri, headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        if (mounted) setState(() => _invoiceById.clear());
        return;
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final rows = (body['data'] as List?) ?? [];
      final fetched = rows
          .whereType<Map<String, dynamic>>()
          .map(_InvoiceOption.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _invoiceById
          ..clear()
          ..addEntries(fetched.map((e) => MapEntry(e.id, e)));
      });
    } catch (_) {
      // Silent.
    } finally {
      if (mounted) setState(() => _loadingInvoices = false);
    }
  }

  Future<void> _openInvoicePicker() async {
    final updated = await showDialog<Set<int>?>(
      context: context,
      builder: (_) => _InvoicePickerDialog(
        invoices: _invoiceById.values.toList()..sort((a, b) {
          final ad = a.billingDate ?? '';
          final bd = b.billingDate ?? '';
          return bd.compareTo(ad);
        }),
        initiallySelected: Set<int>.from(_selectedInvoiceIds),
        onSearch: (q) async {
          await _loadInvoices(hospitalId: _selectedHospital?.id, q: q);
          return _invoiceById.values.toList();
        },
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        _selectedInvoiceIds
          ..clear()
          ..addAll(updated);
      });
    }
  }

  // ── File picker ───────────────────────────────────────────────────────
  Future<void> _pickFiles() async {
    try {
      // Allowed formats: PDF, JPG, JPEG, PNG and ZIP archives.
      // ZIPs are uploaded as-is — the backend unpacks them server-side
      // and feeds each supported entry through the existing pipeline.
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'zip'],
        withData: kIsWeb,
      );
      if (result == null) return;
      final added = <_PickedFile>[];
      String? zipPickedName;
      for (final f in result.files) {
        if (f.size <= 0) continue;
        added.add(_PickedFile(
          name: f.name,
          file: kIsWeb ? null : (f.path != null ? File(f.path!) : null),
          bytes: f.bytes,
          sizeBytes: f.size,
        ));
        if (zipPickedName == null && f.name.toLowerCase().endsWith('.zip')) {
          zipPickedName = f.name;
        }
      }
      if (mounted) setState(() => _files.addAll(added));

      if (zipPickedName != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'ZIP archive selected: $zipPickedName\n'
              'Number of files will be processed after upload.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File picker error: $e')),
        );
      }
    }
  }

  void _removeFile(int index) {
    setState(() => _files.removeAt(index));
  }

  // ── Upload ────────────────────────────────────────────────────────────
  Future<void> _upload() async {
    if (_files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one file first.')),
      );
      return;
    }

    setState(() => _uploading = true);

    // ── Chunked-upload guard ────────────────────────────────────────────
    // If any file in the batch exceeds the 500 MB single-shot ceiling,
    // route the entire batch through the streamed chunked endpoint.
    final bool anyBig = _files.any((f) => f.sizeBytes > kChunkSizeBytes);
    if (anyBig) {
      try {
        await _performChunkedUpload();
      } finally {
        if (mounted) setState(() => _uploading = false);
      }
      return;
    }

    // Compute a payload-aware timeout: req.send() must cover connect + TLS
    // + ALL multipart bytes + first response byte, so a flat 5-min worked
    // for tiny uploads but timed out on slow links once the user batched
    // many PDFs.
    int totalBytes = 0;
    for (final f in _files) {
      totalBytes += f.sizeBytes;
    }
    final int sendSeconds = (60
            + (_files.length * 20)
            + (totalBytes / 50000).ceil())
        .clamp(120, 12 * 60);
    final Duration sendTimeout = Duration(seconds: sendSeconds);
    const int maxRetries = 4;
    const ladder = [4, 8, 16, 30];

    http.Response? finalResp;
    Object? lastError;

    try {
      final token = await _authToken();
      final uri = Uri.parse(Multi_Api_POD_UPLOAD_URL);

      for (int attempt = 0; attempt < maxRetries; attempt++) {
        try {
          // Build a fresh request per attempt — http.MultipartFile streams
          // can only be read once, so reuse across retries doesn't work.
          final req = http.MultipartRequest('POST', uri);
          if (token != null) req.headers['Authorization'] = 'Bearer $token';
          req.headers['Connection'] = 'close';

          // Always send our stockist_id explicitly even though the backend
          // will auto-resolve it — keeps the request self-describing.
          if (_stockistId != null) {
            req.fields['stockist_id'] = _stockistId.toString();
          }
          if (_selectedHospital != null) {
            req.fields['hospital_id'] = _selectedHospital!.id.toString();
          }
          var i = 0;
          for (final invoiceId in _selectedInvoiceIds) {
            req.fields['sales_statement_ids[$i]'] = invoiceId.toString();
            i++;
          }
          req.fields['document_count'] = _files.length.toString();
          req.fields['multi_page'] = (_files.length > 1).toString();

          for (final f in _files) {
            // Derive the correct Content-Type from the file extension so
            // ZIP archives and images aren't sent under application/pdf
            // (the server validates by sniffing content too, but a wrong
            // Content-Type header makes debugging painful).
            final mt = _mediaTypeForName(f.name);
            if (f.file != null) {
              req.files.add(await http.MultipartFile.fromPath(
                'files[]',
                f.file!.path,
                filename: f.name,
                contentType: mt,
              ));
            } else if (f.bytes != null) {
              req.files.add(http.MultipartFile.fromBytes(
                'files[]',
                f.bytes!,
                filename: f.name,
                contentType: mt,
              ));
            }
          }

          // Long upload visibility — keep the user informed.
          ScaffoldMessengerState? messenger;
          if (mounted) {
            messenger = ScaffoldMessenger.of(context);
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _hasZipPicked()
                            ? 'Uploading ZIP… '
                              'attempt ${attempt + 1}/$maxRetries'
                            : 'Uploading ${_files.length} POD(s)… '
                              'attempt ${attempt + 1}/$maxRetries',
                      ),
                    ),
                  ],
                ),
                duration: sendTimeout,
              ),
            );
          }

          final streamed = await req.send().timeout(sendTimeout);
          final resp = await http.Response.fromStream(streamed);
          messenger?.hideCurrentSnackBar();
          finalResp = resp;
          // Only retry on retryable HTTP statuses (5xx / 408 / 429); 4xx
          // and 2xx exit the loop.
          if (resp.statusCode == 408 ||
              resp.statusCode == 429 ||
              resp.statusCode >= 500) {
            if (attempt < maxRetries - 1) {
              final wait = Duration(
                seconds: ladder[attempt.clamp(0, ladder.length - 1)],
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Server is busy (HTTP ${resp.statusCode}). Retrying in ${wait.inSeconds}s…',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
              await Future.delayed(wait);
              continue;
            }
          }
          break;
        } on TimeoutException catch (e) {
          lastError = e;
          if (attempt < maxRetries - 1) {
            final wait = Duration(
              seconds: ladder[attempt.clamp(0, ladder.length - 1)],
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Upload timed out. Retrying in ${wait.inSeconds}s…',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
            await Future.delayed(wait);
            continue;
          }
          rethrow;
        } catch (e) {
          lastError = e;
          // SocketException, ClientException → retryable network errors.
          final s = e.toString().toLowerCase();
          final retryable = e is SocketException
              || s.contains('socketexception')
              || s.contains('connection abort')
              || s.contains('connection reset')
              || s.contains('timed out')
              || s.contains('connection closed');
          if (retryable && attempt < maxRetries - 1) {
            final wait = Duration(
              seconds: ladder[attempt.clamp(0, ladder.length - 1)],
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Network issue while uploading. Retrying in ${wait.inSeconds}s…',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
            await Future.delayed(wait);
            continue;
          }
          rethrow;
        }
      }

      if (finalResp == null) {
        throw lastError ?? Exception('Upload failed without a response.');
      }
      final resp = finalResp;

      if (!mounted) return;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = jsonDecode(resp.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Uploaded ${_files.length} POD(s). Background processing started.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _files.clear();
          _selectedInvoiceIds.clear();
        });

        // Reuse the existing upload-status screen so the user sees the same
        // progress UI the KAM flow uses.
        if (body is Map<String, dynamic>) {
          Navigator.of(context).pushNamed(
            AppRoutes.uploadStatus,
            arguments: {
              'uploadData': body,
              'totalFiles': (body['data']?['total_files'] as num?)?.toInt() ?? 0,
            },
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${resp.statusCode} ${resp.body}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ModernUIComponents.buildModernAppBar(
        title: 'Upload PODs',
        subtitle: _stockistName ?? 'Stockist',
        icon: Icons.cloud_upload,
        color: const Color(0xFF00A0A8),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStockistCard(),
            const SizedBox(height: 16),
            _buildHospitalSection(),
            const SizedBox(height: 16),
            _buildInvoiceSection(),
            const SizedBox(height: 16),
            _buildFilesSection(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            onPressed: _uploading ? null : _upload,
            icon: _uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(Icons.upload),
            label: Text(_uploading
                ? 'Uploading…'
                : 'Upload ${_files.length} POD${_files.length == 1 ? '' : 's'}'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A0A8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStockistCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.store, color: Color(0xFF00A0A8)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Logged in as stockist',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _stockistName ?? '—',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((_stockistCode ?? '').isNotEmpty)
                    Text(
                      'Code: $_stockistCode',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHospitalSection() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_hospital_outlined, color: Color(0xFF00A0A8)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Hospital (optional)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_selectedHospital != null)
                  TextButton.icon(
                    onPressed: _clearHospital,
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _openHospitalPicker,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _selectedHospital == null
                          ? const Text(
                              'Tap to pick a hospital — leave blank if none applies.',
                              style: TextStyle(color: Colors.black54),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedHospital!.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if ((_selectedHospital!.btstCode ?? '').isNotEmpty)
                                  Text(
                                    'BTST: ${_selectedHospital!.btstCode}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    if (_loadingHospitals)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceSection() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined, color: Color(0xFF00A0A8)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Invoices (optional)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_selectedInvoiceIds.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(_selectedInvoiceIds.clear),
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () async {
                if (_invoiceById.isEmpty && !_loadingInvoices) {
                  await _loadInvoices(
                    hospitalId: _selectedHospital?.id,
                  );
                }
                if (mounted) _openInvoicePicker();
              },
              icon: const Icon(Icons.list_alt),
              label: Text(_selectedInvoiceIds.isEmpty
                  ? 'Pick invoices'
                  : '${_selectedInvoiceIds.length} invoice(s) selected — change'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
            ),
            if (_selectedInvoiceIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _selectedInvoiceIds.map((id) {
                  final inv = _invoiceById[id];
                  final label = inv == null
                      ? 'Invoice #$id'
                      : (inv.invoiceNumber ?? 'Invoice #$id');
                  return Chip(
                    label: Text(label, style: const TextStyle(fontSize: 11)),
                    onDeleted: () =>
                        setState(() => _selectedInvoiceIds.remove(id)),
                    deleteIconColor: Colors.deepPurple,
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              _selectedHospital == null
                  ? 'All sales invoices for your stockist will be listed.'
                  : 'Showing only invoices for "${_selectedHospital!.name}".',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilesSection() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.picture_as_pdf, color: Color(0xFF00A0A8)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'POD files',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Files'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_files.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No PDFs picked yet.',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            else
              Column(
                children: List.generate(_files.length, (i) {
                  final f = _files[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    dense: true,
                    leading: const Icon(Icons.description, color: Colors.redAccent),
                    title: Text(f.name, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      '${(f.sizeBytes / 1024).toStringAsFixed(1)} KB',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _removeFile(i),
                    ),
                  );
                }),
              ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  /// Streamed chunked upload for batches that contain any file > 500 MB.
  /// Each picked file is uploaded individually via ChunkedUploader; the
  /// server reassembles and dispatches the SAME OCR pipeline a one-shot
  /// upload would.
  Future<void> _performChunkedUpload() async {
    final token = await _authToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not signed in — please log in and retry.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final Map<String, String> baseContext = {};
    if (_stockistId != null) {
      baseContext['stockist_id'] = _stockistId.toString();
    }
    if (_selectedHospital != null) {
      baseContext['hospital_id'] = _selectedHospital!.id.toString();
    }
    var i = 0;
    for (final invoiceId in _selectedInvoiceIds) {
      baseContext['sales_statement_ids[$i]'] = invoiceId.toString();
      i++;
    }

    int? lastBatchDbId;
    String? lastExternalBatchId;
    ScaffoldMessengerState? messenger;
    if (mounted) messenger = ScaffoldMessenger.of(context);

    for (int idx = 0; idx < _files.length; idx++) {
      final f = _files[idx];
      final fileLabel = f.name;
      final int totalFilesInBatch = _files.length;

      void showProgress(ChunkUploadProgress p) {
        if (!mounted) return;
        final pct = p.percent.toStringAsFixed(0);
        final etaSec = p.estimatedRemaining?.inSeconds;
        final etaTxt = etaSec == null || etaSec <= 0 ? '' : ' — ~${etaSec}s left';
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Uploading $fileLabel '
                  '(file ${idx + 1}/$totalFilesInBatch)\n'
                  'Chunk ${p.chunkIndex} of ${p.totalChunks} — $pct%$etaTxt',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          duration: const Duration(minutes: 30),
        ));
      }

      final uploader = ChunkedUploader(
        authToken: token,
        context: baseContext,
        onProgress: showProgress,
      );

      ChunkUploadResult result;
      try {
        if (f.file != null) {
          result = await uploader.upload(f.file!);
        } else if (f.bytes != null) {
          // FilePicker's bytes are typed List<int> on _PickedFile; the
          // uploader needs a Uint8List view for sublist() to stay efficient.
          result = await uploader.uploadBytes(
            fileName: fileLabel,
            bytes: Uint8List.fromList(f.bytes!),
          );
        } else {
          continue;
        }
      } catch (e) {
        if (mounted) {
          messenger?.hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Upload error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (!result.success) {
        if (mounted) {
          messenger?.hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Upload failed: ${result.message ?? result.error ?? "Unknown error"}',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      lastBatchDbId = result.podUploadBatchId;
      lastExternalBatchId = result.externalBatchId;
    }

    if (mounted) {
      messenger?.hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload complete — processing on server.'),
          backgroundColor: Colors.green,
        ),
      );
      if (lastBatchDbId != null) {
        Navigator.pushReplacementNamed(
          context,
          AppRoutes.uploadStatus,
          arguments: {
            'uploadData': {
              'success': true,
              'data': {
                'batch_id': lastExternalBatchId ?? lastBatchDbId.toString(),
                'batch_db_id': lastBatchDbId,
              },
            },
            'totalFiles': _files.length,
          },
        );
      }
      setState(() => _files.clear());
    }
  }

  /// Map a filename to the correct multipart Content-Type. Only the
  /// extensions we accept in the picker are listed; anything else falls
  /// back to application/octet-stream and the server's MIME sniffer
  /// figures it out.
  MediaType _mediaTypeForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.zip')) return MediaType('application', 'zip');
    if (lower.endsWith('.pdf')) return MediaType('application', 'pdf');
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return MediaType('image', 'jpeg');
    }
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    return MediaType('application', 'octet-stream');
  }

  /// True if the current batch about to be uploaded contains any .zip
  /// archive — used to tailor the in-flight upload progress message.
  bool _hasZipPicked() {
    for (final f in _files) {
      if (f.name.toLowerCase().endsWith('.zip')) return true;
    }
    return false;
  }
}

// ── Models ──────────────────────────────────────────────────────────────
class _HospitalOption {
  final int id;
  final String name;
  final String? btstCode;
  final String? city;
  final String? address;
  _HospitalOption({
    required this.id,
    required this.name,
    this.btstCode,
    this.city,
    this.address,
  });
  factory _HospitalOption.fromJson(Map<String, dynamic> j) => _HospitalOption(
        id: (j['hospital_id'] as num).toInt(),
        name: (j['name'] ?? '').toString(),
        btstCode: j['btst_code']?.toString(),
        city: j['city']?.toString(),
        address: j['address']?.toString(),
      );
}

class _InvoiceOption {
  final int id;
  final String? invoiceNumber;
  final String? billingDate;
  final String? hospitalName;
  final String? btstCode;
  final num? total;
  _InvoiceOption({
    required this.id,
    this.invoiceNumber,
    this.billingDate,
    this.hospitalName,
    this.btstCode,
    this.total,
  });
  factory _InvoiceOption.fromJson(Map<String, dynamic> j) => _InvoiceOption(
        id: (j['id'] as num).toInt(),
        invoiceNumber: j['invoice_number']?.toString(),
        billingDate: j['billing_date']?.toString(),
        hospitalName: j['hospital_name']?.toString(),
        btstCode: j['btst_code']?.toString(),
        total: j['total'] is num ? j['total'] as num : num.tryParse('${j['total'] ?? ''}'),
      );
}

class _PickedFile {
  final String name;
  final File? file;
  final List<int>? bytes;
  final int sizeBytes;
  _PickedFile({
    required this.name,
    this.file,
    this.bytes,
    required this.sizeBytes,
  });
}

// ── Hospital picker dialog ──────────────────────────────────────────────
class _HospitalPickerDialog extends StatefulWidget {
  final List<_HospitalOption> initial;
  final Future<List<_HospitalOption>> Function(String q) onSearch;
  const _HospitalPickerDialog({
    required this.initial,
    required this.onSearch,
  });

  @override
  State<_HospitalPickerDialog> createState() => _HospitalPickerDialogState();
}

class _HospitalPickerDialogState extends State<_HospitalPickerDialog> {
  late List<_HospitalOption> _rows = widget.initial;
  bool _loading = false;
  Timer? _debounce;
  final _ctrl = TextEditingController();

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _loading = true);
      try {
        final rows = await widget.onSearch(q);
        if (!mounted) return;
        setState(() => _rows = rows);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pick hospital'),
      content: SizedBox(
        width: 460,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: 'Search master by name, BTST, address, or city',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_rows.isEmpty
                      ? const Center(child: Text('No matches.'))
                      : ListView.separated(
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final h = _rows[i];
                            // Build a single-line address: "<street>, <city>"
                            // when both exist, otherwise whichever is set.
                            // Helps stockists tell apart hospitals that
                            // share names across cities.
                            final addrParts = <String>[
                              if ((h.address ?? '').trim().isNotEmpty) h.address!.trim(),
                              if ((h.city ?? '').trim().isNotEmpty) h.city!.trim(),
                            ];
                            final addressLine = addrParts.join(', ');
                            return ListTile(
                              dense: true,
                              isThreeLine: addressLine.isNotEmpty,
                              title: Text(
                                h.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (addressLine.isNotEmpty)
                                    Text(
                                      addressLine,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black87,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  if ((h.btstCode ?? '').isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'BTST: ${h.btstCode}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.deepPurple,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              onTap: () => Navigator.of(context).pop(h),
                            );
                          },
                        )),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

// ── Invoice picker dialog (multi-select) ────────────────────────────────
class _InvoicePickerDialog extends StatefulWidget {
  final List<_InvoiceOption> invoices;
  final Set<int> initiallySelected;
  final Future<List<_InvoiceOption>> Function(String q) onSearch;
  const _InvoicePickerDialog({
    required this.invoices,
    required this.initiallySelected,
    required this.onSearch,
  });

  @override
  State<_InvoicePickerDialog> createState() => _InvoicePickerDialogState();
}

class _InvoicePickerDialogState extends State<_InvoicePickerDialog> {
  late List<_InvoiceOption> _rows = widget.invoices;
  late final Set<int> _picked = {...widget.initiallySelected};
  bool _loading = false;
  Timer? _debounce;
  final _ctrl = TextEditingController();

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _loading = true);
      try {
        final rows = await widget.onSearch(q);
        if (!mounted) return;
        setState(() => _rows = rows);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Pick invoices (${_picked.length} selected)'),
      content: SizedBox(
        width: 480,
        height: 500,
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: 'Search by invoice number, BTST, or hospital',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_rows.isEmpty
                      ? const Center(child: Text('No invoices found.'))
                      : ListView.separated(
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final inv = _rows[i];
                            final checked = _picked.contains(inv.id);
                            return CheckboxListTile(
                              dense: true,
                              value: checked,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _picked.add(inv.id);
                                  } else {
                                    _picked.remove(inv.id);
                                  }
                                });
                              },
                              title: Text(inv.invoiceNumber ?? 'Invoice #${inv.id}'),
                              subtitle: Text([
                                if ((inv.hospitalName ?? '').isNotEmpty) inv.hospitalName,
                                if ((inv.billingDate ?? '').isNotEmpty) inv.billingDate,
                                if (inv.total != null) '₹${inv.total}',
                              ].whereType<String>().join(' • ')),
                            );
                          },
                        )),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_picked),
          child: Text('Apply (${_picked.length})'),
        ),
      ],
    );
  }
}
