class Pod {
  final int id;
  final String podNumber;
  final String invoiceNumber;
  final String podDate; // ISO string as received
  final String invoiceDate; // ISO string as received

  Pod({
    required this.id,
    required this.podNumber,
    required this.invoiceNumber,
    required this.podDate,
    required this.invoiceDate,
  });

  factory Pod.fromJson(Map<String, dynamic> json) {
    return Pod(
      id: (json['id'] is int)
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      podNumber: (json['pod_number'] ?? '').toString(),
      invoiceNumber: (json['invoice_number'] ?? '').toString(),
      podDate: (json['pod_date'] ?? '').toString(),
      invoiceDate: (json['invoice_date'] ?? '').toString(),
    );
  }

  String displayLabel() => 'POD: $podNumber  |  INV: $invoiceNumber';
}
