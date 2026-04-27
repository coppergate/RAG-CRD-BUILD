// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'memory_retrieve_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MemoryRetrieveRequest _$MemoryRetrieveRequestFromJson(
  Map<String, dynamic> json,
) => _MemoryRetrieveRequest(
  query: json['query'] as String,
  sessionId: json['sessionId'] as String?,
  userId: json['userId'] as String?,
  limit: (json['limit'] as num?)?.toInt() ?? 10,
  filters: json['filters'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$MemoryRetrieveRequestToJson(
  _MemoryRetrieveRequest instance,
) => <String, dynamic>{
  'query': instance.query,
  'sessionId': instance.sessionId,
  'userId': instance.userId,
  'limit': instance.limit,
  'filters': instance.filters,
};
