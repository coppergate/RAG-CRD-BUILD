// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'response_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ResponseMessage _$ResponseMessageFromJson(Map<String, dynamic> json) =>
    _ResponseMessage(
      content: json['content'] as String,
      sessionId: json['sessionId'] as String?,
      messageId: json['messageId'] as String?,
      role: json['role'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      timestamp: json['timestamp'] == null
          ? null
          : DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$ResponseMessageToJson(_ResponseMessage instance) =>
    <String, dynamic>{
      'content': instance.content,
      'sessionId': instance.sessionId,
      'messageId': instance.messageId,
      'role': instance.role,
      'metadata': instance.metadata,
      'timestamp': instance.timestamp?.toIso8601String(),
    };
