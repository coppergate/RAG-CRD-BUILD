import 'package:freezed_annotation/freezed_annotation.dart';

part 'memory_write_request.freezed.dart';
part 'memory_write_request.g.dart';

@freezed
abstract class MemoryWriteRequest with _$MemoryWriteRequest {
  const factory MemoryWriteRequest({
    required String content,
    @Default('short') String type,
    double? salience,
    String? sessionId,
    String? userId,
    Map<String, dynamic>? metadata,
  }) = _MemoryWriteRequest;

  factory MemoryWriteRequest.fromJson(Map<String, dynamic> json) => _$MemoryWriteRequestFromJson(json);
}
