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
    // Helper to safely convert to String
    String? _safeString(dynamic value) {
      if (value == null) return null;
      if (value is String) return value;
      if (value is List && value.isNotEmpty) {
        // If it's a list, take the first element and convert to string
        return value.first.toString();
      }
      return value.toString();
    }

    // Helper to safely convert to int
    int _safeInt(dynamic value, int defaultValue) {
      if (value == null) return defaultValue;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    // Helper to safely convert to Map
    Map<String, dynamic>? _safeMap(dynamic value) {
      if (value == null) return null;
      if (value is Map<String, dynamic>) return value;
      if (value is Map) {
        try {
          return Map<String, dynamic>.from(value);
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    return Batch(
      id: _safeInt(json['id'], 0),
      userId: _safeInt(json['user_id'], 0),
      hospitalId: _safeInt(json['hospital_id'], 0),
      stockistId: _safeInt(json['stockist_id'], 0),
      totalFiles: _safeInt(json['total_files'], 0),
      successfulFiles: _safeInt(json['successful_files'], 0),
      failedFiles: _safeInt(json['failed_files'], 0),
      cancelledFiles: _safeInt(json['cancelled_files'], 0),
      status: _safeString(json['status']) ?? 'unknown',
      startedAt: _safeString(json['started_at']),
      completedAt: _safeString(json['completed_at']),
      steps: _safeMap(json['steps']) ?? {},
      failureReasons: _safeString(json['failure_reasons']),
      metadata: _safeMap(json['metadata']) ?? {},
      createdAt: _safeString(json['created_at']) ?? '',
      updatedAt: _safeString(json['updated_at']) ?? '',
      user: _safeMap(json['user']),
      hospital: _safeMap(json['hospital']),
      stockist: _safeMap(json['stockist']),
    );
  }

  String get hospitalName {
    final name = hospital?['name'];
    if (name == null) return 'Unknown Hospital';
    if (name is String) return name;
    if (name is List && name.isNotEmpty) return name.first.toString();
    return name.toString();
  }
  
  String get stockistName {
    final name = stockist?['name'];
    if (name == null) return 'Unknown Stockist';
    if (name is String) return name;
    if (name is List && name.isNotEmpty) return name.first.toString();
    return name.toString();
  }
  
  String get userName {
    final name = user?['name'];
    if (name == null) return 'Unknown User';
    if (name is String) return name;
    if (name is List && name.isNotEmpty) return name.first.toString();
    return name.toString();
  }
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
    // Helper to safely convert to String
    String? _safeString(dynamic value) {
      if (value == null) return null;
      if (value is String) return value;
      if (value is List && value.isNotEmpty) {
        return value.first.toString();
      }
      return value.toString();
    }

    // Helper to safely convert to int
    int _safeInt(dynamic value, int defaultValue) {
      if (value == null) return defaultValue;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    // Helper to safely convert to nullable int
    int? _safeIntNullable(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      return null;
    }

    final List<dynamic> dataList = json['data'] is List ? json['data'] as List<dynamic> : [];
    return BatchListResponse(
      currentPage: _safeInt(json['current_page'], 1),
      data: dataList
          .map((e) {
            try {
              if (e == null) return null;
              Map<String, dynamic>? batchMap;
              if (e is Map<String, dynamic>) {
                batchMap = e;
              } else if (e is Map) {
                try {
                  batchMap = Map<String, dynamic>.from(e);
                } catch (_) {
                  return null;
                }
              } else {
                return null;
              }
              return Batch.fromJson(batchMap);
            } catch (err) {
              print('Error parsing batch item: $err');
              return null;
            }
          })
          .whereType<Batch>()
          .toList(),
      lastPage: _safeIntNullable(json['last_page']),
      total: _safeInt(json['total'], 0),
      perPage: _safeInt(json['per_page'], 25),
      nextPageUrl: _safeString(json['next_page_url']),
      prevPageUrl: _safeString(json['prev_page_url']),
    );
  }
}

