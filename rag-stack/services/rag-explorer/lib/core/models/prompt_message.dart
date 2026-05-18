import 'package:freezed_annotation/freezed_annotation.dart';

part 'prompt_message.freezed.dart';
part 'prompt_message.g.dart';

@freezed
abstract class PromptMessage with _$PromptMessage {
  const factory PromptMessage({
    required String prompt,
    String? sessionId,
    String? plannerModel,
    String? executorModel,
    List<String>? tags,
    @Default('off') String memoryMode,
  }) = _PromptMessage;

  factory PromptMessage.fromJson(Map<String, dynamic> json) => _$PromptMessageFromJson(json);
}
