import 'dart:math';

class HospitalStats {
  final String id;
  final String name;
  final String zone;
  final double salesValue; // Total sales value
  final double podValue; // Total value covered by PODs uploaded
  final int podCount; // Number of POD documents
  final int records; // Number of records considered (optional)
  final DateTime? updatedAt;

  HospitalStats({
    required this.id,
    required this.name,
    required this.zone,
    required this.salesValue,
    required this.podValue,
    required this.podCount,
    required this.records,
    this.updatedAt,
  });

  double get percentUploaded {
    if (salesValue <= 0) return 0;
    final pct = (podValue / salesValue) * 100.0;
    if (pct.isNaN || pct.isInfinite) return 0;
    return max(0, min(100, pct));
  }

  static double _parseAmount(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) {
      final cleaned = v.replaceAll(RegExp(r'[^0-9.]'), '');
      if (cleaned.isEmpty) return 0;
      return double.tryParse(cleaned) ?? 0;
    }
    return 0;
  }

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final cleaned = v.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleaned.isEmpty) return 0;
      return int.tryParse(cleaned) ?? 0;
    }
    return 0;
  }

  factory HospitalStats.fromJson(Map<String, dynamic> m) {
    String pickString(List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
        if (v is num) return v.toString();
      }
      return '';
    }

    DateTime? parseDate(dynamic v) {
      if (v is String && v.isNotEmpty) {
        try {
          return DateTime.parse(v);
        } catch (_) {}
      }
      return null;
    }

    final id = pickString(['id', 'hospitalId', 'code', 'hospital_code']);
    final name = pickString([
      'name',
      'hospital',
      'hospitalName',
      'displayName',
    ]);
    final zone = pickString(['zone', 'region', 'area']);

    final sales = _parseAmount(
      m['sales'] ?? m['salesValue'] ?? m['total_sales'],
    );
    final podVal = _parseAmount(
      m['podValue'] ?? m['pod_value'] ?? m['uploaded_value'],
    );
    final podCnt = _parseInt(m['podCount'] ?? m['pod_count'] ?? m['documents']);
    final recs = _parseInt(m['records'] ?? m['txns'] ?? m['count']);
    final updatedAt = parseDate(
      m['updatedAt'] ?? m['updated_at'] ?? m['last_sync'],
    );

    return HospitalStats(
      id: id.isEmpty ? name : id,
      name: name.isEmpty ? 'Hospital $id' : name,
      zone: zone.isEmpty ? '-' : zone,
      salesValue: sales,
      podValue: podVal,
      podCount: podCnt,
      records: recs,
      updatedAt: updatedAt,
    );
  }
}
