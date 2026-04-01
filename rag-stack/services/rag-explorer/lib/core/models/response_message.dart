import 'package:freezed_annotation/freezed_annotation.dart';

part 'response_message.freezed.dart';
part 'response_message.g.dart';

@freezed
class ResponseMessage with _$ResponseMessage {
  const factory ResponseMessage({
    required String content,
    String? sessionId,
    String? messageId,
    String? role,
    Map<String, dynamic>? metadata,
    DateTime? timestamp,
  }) = _ResponseMessage;

  factory ResponseMessage.fromJson(Map<String, dynamic> json) => _$ResponseMessageFromJson(json);
}
