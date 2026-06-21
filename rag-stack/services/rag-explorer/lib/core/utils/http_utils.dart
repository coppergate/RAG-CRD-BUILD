import 'package:dio/dio.dart';

extension ResponseSuccess on Response {
  bool get isSuccess => (statusCode ?? 0) >= 200 && statusCode! < 300;
}

/// Safely converts a dynamic value to Map<String, dynamic>.
/// Returns an empty map for null or non-map inputs.
Map<String, dynamic> asStringMap(dynamic data) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  return const {};
}

/// Safely converts a dynamic value to List<Map<String, dynamic>>.
/// Returns an empty list for null or non-list inputs.
List<Map<String, dynamic>> asStringMapList(dynamic data) {
  if (data is! List) return const [];
  return data.map(asStringMap).where((m) => m.isNotEmpty).toList();
}
