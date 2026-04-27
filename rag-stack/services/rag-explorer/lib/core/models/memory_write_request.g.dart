// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'memory_write_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MemoryWriteRequest _$MemoryWriteRequestFromJson(Map<String, dynamic> json) =>
    _MemoryWriteRequest(
      content: json['content'] as String,
      type: json['type'] as String? ?? 'short',
      salience: (json['salience'] as num?)?.toDouble(),
      sessionId: json['sessionId'] as String?,
      userId: json['userId'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$MemoryWriteRequestToJson(_MemoryWriteRequest instance) =>
    <String, dynamic>{
      'content': instance.content,
      'type': instance.type,
      'salience': instance.salience,
      'sessionId': instance.sessionId,
      'userId': instance.userId,
      'metadata': instance.metadata,
    };
