// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'prompt_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PromptMessage _$PromptMessageFromJson(Map<String, dynamic> json) =>
    _PromptMessage(
      prompt: json['prompt'] as String,
      sessionId: json['sessionId'] as String?,
      plannerModel: json['plannerModel'] as String?,
      executorModel: json['executorModel'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
      memoryMode: json['memoryMode'] as String? ?? 'off',
    );

Map<String, dynamic> _$PromptMessageToJson(_PromptMessage instance) =>
    <String, dynamic>{
      'prompt': instance.prompt,
      'sessionId': instance.sessionId,
      'plannerModel': instance.plannerModel,
      'executorModel': instance.executorModel,
      'tags': instance.tags,
      'memoryMode': instance.memoryMode,
    };
