// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'prompt_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$PromptMessageImpl _$$PromptMessageImplFromJson(Map<String, dynamic> json) =>
    _$PromptMessageImpl(
      prompt: json['prompt'] as String,
      sessionId: json['sessionId'] as String?,
      plannerModel: json['plannerModel'] as String?,
      executorModel: json['executorModel'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
      memoryMode: json['memoryMode'] as String? ?? 'off',
    );

Map<String, dynamic> _$$PromptMessageImplToJson(_$PromptMessageImpl instance) =>
    <String, dynamic>{
      'prompt': instance.prompt,
      'sessionId': instance.sessionId,
      'plannerModel': instance.plannerModel,
      'executorModel': instance.executorModel,
      'tags': instance.tags,
      'memoryMode': instance.memoryMode,
    };
