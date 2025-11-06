class Batch {
  final int id;
  final int userId;
  final int hospitalId;
  final int stockistId;
  final int totalFiles;
  final int successfulFiles;
  final int failedFiles;
  final int cancelledFiles;
  final String status;
  final String? startedAt;
  final String? completedAt;
  final Map<String, dynamic> steps;
  final String? failureReasons;
  final Map<String, dynamic> metadata;
  final String createdAt;
  final String updatedAt;
  final Map<String, dynamic>? user;
  final Map<String, dynamic>? hospital;
  final Map<String, dynamic>? stockist;

  Batch({
    required this.id,
    required this.userId,
    required this.hospitalId,
    required this.stockistId,
    required this.totalFiles,
    required this.successfulFiles,
    required this.failedFiles,
    required this.cancelledFiles,
    required this.status,
    this.startedAt,
    this.completedAt,
    required this.steps,
    this.failureReasons,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
    this.user,
    this.hospital,
    this.stockist,
  });

  factory Batch.fromJson(Map<String, dynamic> json) {
    return Batch(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      hospitalId: json['hospital_id'] as int,
      stockistId: json['stockist_id'] as int,
      totalFiles: json['total_files'] as int? ?? 0,
      successfulFiles: json['successful_files'] as int? ?? 0,
      failedFiles: json['failed_files'] as int? ?? 0,
      cancelledFiles: json['cancelled_files'] as int? ?? 0,
      status: json['status'] as String? ?? 'unknown',
      startedAt: json['started_at'] as String?,
      completedAt: json['completed_at'] as String?,
      steps: json['steps'] as Map<String, dynamic>? ?? {},
      failureReasons: json['failure_reasons'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
      user: json['user'] as Map<String, dynamic>?,
      hospital: json['hospital'] as Map<String, dynamic>?,
      stockist: json['stockist'] as Map<String, dynamic>?,
    );
  }

  String get hospitalName => hospital?['name'] as String? ?? 'Unknown Hospital';
  String get stockistName => stockist?['name'] as String? ?? 'Unknown Stockist';
  String get userName => user?['name'] as String? ?? 'Unknown User';
}

class BatchListResponse {
  final int currentPage;
  final List<Batch> data;
  final int? lastPage;
  final int total;
  final int perPage;
  final String? nextPageUrl;
  final String? prevPageUrl;

  BatchListResponse({
    required this.currentPage,
    required this.data,
    this.lastPage,
    required this.total,
    required this.perPage,
    this.nextPageUrl,
    this.prevPageUrl,
  });

  factory BatchListResponse.fromJson(Map<String, dynamic> json) {
    final List<dynamic> dataList = json['data'] as List<dynamic>? ?? [];
    return BatchListResponse(
      currentPage: json['current_page'] as int? ?? 1,
      data: dataList.map((e) => Batch.fromJson(e as Map<String, dynamic>)).toList(),
      lastPage: json['last_page'] as int?,
      total: json['total'] as int? ?? 0,
      perPage: json['per_page'] as int? ?? 25,
      nextPageUrl: json['next_page_url'] as String?,
      prevPageUrl: json['prev_page_url'] as String?,
    );
  }
}

