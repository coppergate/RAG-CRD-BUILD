import 'package:freezed_annotation/freezed_annotation.dart';

part 'memory_retrieve_request.freezed.dart';
part 'memory_retrieve_request.g.dart';

@freezed
abstract class MemoryRetrieveRequest with _$MemoryRetrieveRequest {
  const factory MemoryRetrieveRequest({
    required String query,
    int? sessionId,
    String? userId,
    @Default(10) int limit,
    Map<String, dynamic>? filters,
  }) = _MemoryRetrieveRequest;

  factory MemoryRetrieveRequest.fromJson(Map<String, dynamic> json) => _$MemoryRetrieveRequestFromJson(json);
}
