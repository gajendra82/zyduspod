class Pod {
  final int id;
  final String podNumber;
  final String invoiceNumber;
  final String podDate; // ISO string as received
  final String invoiceDate; // ISO string as received
  final EInvoice? eInvoice; // Optional e-invoice data

  Pod({
    required this.id,
    required this.podNumber,
    required this.invoiceNumber,
    required this.podDate,
    required this.invoiceDate,
    this.eInvoice,
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
      eInvoice: json['e_invoice'] != null 
          ? EInvoice.fromJson(json['e_invoice'])
          : null,
    );
  }

  String displayLabel() => 'POD: $podNumber  |  INV: $invoiceNumber';
}

class EInvoice {
  final int id;
  final String invoiceNumber;
  final String irn;
  final String? ackNo;
  final int podId;
  final int stockistId;
  final int hospitalId;
  final String invoiceDate;
  final String? dueDate;
  final String totalAmount;
  final String taxAmount;
  final String discountAmount;
  final String status;
  final String gstStatus;
  final String? gstResponse;
  final String? filePath;
  final String? qrCodePath;
  final String? remarks;
  final EInvoiceMetadata? metadata;
  final int createdBy;
  final int? updatedBy;
  final String createdAt;
  final String updatedAt;

  EInvoice({
    required this.id,
    required this.invoiceNumber,
    required this.irn,
    this.ackNo,
    required this.podId,
    required this.stockistId,
    required this.hospitalId,
    required this.invoiceDate,
    this.dueDate,
    required this.totalAmount,
    required this.taxAmount,
    required this.discountAmount,
    required this.status,
    required this.gstStatus,
    this.gstResponse,
    this.filePath,
    this.qrCodePath,
    this.remarks,
    this.metadata,
    required this.createdBy,
    this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EInvoice.fromJson(Map<String, dynamic> json) {
    return EInvoice(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}') ?? 0,
      invoiceNumber: (json['invoice_number'] ?? '').toString(),
      irn: (json['irn'] ?? '').toString(),
      ackNo: json['ack_no']?.toString(),
      podId: json['pod_id'] is int ? json['pod_id'] : int.tryParse('${json['pod_id']}') ?? 0,
      stockistId: json['stockist_id'] is int ? json['stockist_id'] : int.tryParse('${json['stockist_id']}') ?? 0,
      hospitalId: json['hospital_id'] is int ? json['hospital_id'] : int.tryParse('${json['hospital_id']}') ?? 0,
      invoiceDate: (json['invoice_date'] ?? '').toString(),
      dueDate: json['due_date']?.toString(),
      totalAmount: (json['total_amount'] ?? '0.00').toString(),
      taxAmount: (json['tax_amount'] ?? '0.00').toString(),
      discountAmount: (json['discount_amount'] ?? '0.00').toString(),
      status: (json['status'] ?? '').toString(),
      gstStatus: (json['gst_status'] ?? '').toString(),
      gstResponse: json['gst_response']?.toString(),
      filePath: json['file_path']?.toString(),
      qrCodePath: json['qr_code_path']?.toString(),
      remarks: json['remarks']?.toString(),
      metadata: json['metadata'] != null 
          ? EInvoiceMetadata.fromJson(json['metadata'])
          : null,
      createdBy: json['created_by'] is int ? json['created_by'] : int.tryParse('${json['created_by']}') ?? 0,
      updatedBy: json['updated_by'] is int ? json['updated_by'] : (json['updated_by'] != null ? int.tryParse('${json['updated_by']}') : null),
      createdAt: (json['created_at'] ?? '').toString(),
      updatedAt: (json['updated_at'] ?? '').toString(),
    );
  }
}

class EInvoiceMetadata {
  final String docType;
  final String irnDate;
  final int itemCount;
  final String buyerGstin;
  final String sellerGstin;
  final String mainHsnCode;
  final String extractedFrom;

  EInvoiceMetadata({
    required this.docType,
    required this.irnDate,
    required this.itemCount,
    required this.buyerGstin,
    required this.sellerGstin,
    required this.mainHsnCode,
    required this.extractedFrom,
  });

  factory EInvoiceMetadata.fromJson(Map<String, dynamic> json) {
    return EInvoiceMetadata(
      docType: (json['doc_type'] ?? '').toString(),
      irnDate: (json['irn_date'] ?? '').toString(),
      itemCount: json['item_count'] is int ? json['item_count'] : int.tryParse('${json['item_count']}') ?? 0,
      buyerGstin: (json['buyer_gstin'] ?? '').toString(),
      sellerGstin: (json['seller_gstin'] ?? '').toString(),
      mainHsnCode: (json['main_hsn_code'] ?? '').toString(),
      extractedFrom: (json['extracted_from'] ?? '').toString(),
    );
  }
}
