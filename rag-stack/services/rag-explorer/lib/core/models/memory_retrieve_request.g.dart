// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'memory_retrieve_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$MemoryRetrieveRequestImpl _$$MemoryRetrieveRequestImplFromJson(
        Map<String, dynamic> json) =>
    _$MemoryRetrieveRequestImpl(
      query: json['query'] as String,
      sessionId: json['sessionId'] as String?,
      userId: json['userId'] as String?,
      limit: (json['limit'] as num?)?.toInt() ?? 10,
      filters: json['filters'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$$MemoryRetrieveRequestImplToJson(
        _$MemoryRetrieveRequestImpl instance) =>
    <String, dynamic>{
      'query': instance.query,
      'sessionId': instance.sessionId,
      'userId': instance.userId,
      'limit': instance.limit,
      'filters': instance.filters,
    };
