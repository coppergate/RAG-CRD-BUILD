// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'metrics.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_QdrantStats _$QdrantStatsFromJson(Map<String, dynamic> json) => _QdrantStats(
  status: json['status'] as String,
  pointsCount: (json['points_count'] as num).toInt(),
  segmentsCount: (json['segments_count'] as num).toInt(),
  indexedVectorsCount: (json['indexed_vectors_count'] as num?)?.toInt(),
  payloadSchema: json['payload_schema'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$QdrantStatsToJson(_QdrantStats instance) =>
    <String, dynamic>{
      'status': instance.status,
      'points_count': instance.pointsCount,
      'segments_count': instance.segmentsCount,
      'indexed_vectors_count': instance.indexedVectorsCount,
      'payload_schema': instance.payloadSchema,
    };

_ModelPerformance _$ModelPerformanceFromJson(Map<String, dynamic> json) =>
    _ModelPerformance(
      modelName: json['model_name'] as String,
      node: json['node'] as String,
      avgTokensPerSec: (json['avg_tokens_per_sec'] as num).toDouble(),
      avgLatencyMs: (json['avg_latency_ms'] as num).toDouble(),
      totalExecutions: (json['total_executions'] as num).toInt(),
    );

Map<String, dynamic> _$ModelPerformanceToJson(_ModelPerformance instance) =>
    <String, dynamic>{
      'model_name': instance.modelName,
      'node': instance.node,
      'avg_tokens_per_sec': instance.avgTokensPerSec,
      'avg_latency_ms': instance.avgLatencyMs,
      'total_executions': instance.totalExecutions,
    };

_SessionHealth _$SessionHealthFromJson(Map<String, dynamic> json) =>
    _SessionHealth(
      sessionId: json['session_id'] as String,
      totalRequests: (json['total_requests'] as num).toInt(),
      successfulRequests: (json['successful_requests'] as num).toInt(),
      successRate: (json['success_rate'] as num).toDouble(),
      avgLatencyMs: (json['avg_latency_ms'] as num?)?.toDouble(),
      totalTokens: (json['total_tokens'] as num?)?.toInt(),
      promptCount: (json['prompt_count'] as num?)?.toInt(),
      responseCount: (json['response_count'] as num?)?.toInt(),
      memoryCount: (json['memory_count'] as num?)?.toInt(),
      tagCount: (json['tag_count'] as num?)?.toInt(),
      status: json['status'] as String,
    );

Map<String, dynamic> _$SessionHealthToJson(_SessionHealth instance) =>
    <String, dynamic>{
      'session_id': instance.sessionId,
      'total_requests': instance.totalRequests,
      'successful_requests': instance.successfulRequests,
      'success_rate': instance.successRate,
      'avg_latency_ms': instance.avgLatencyMs,
      'total_tokens': instance.totalTokens,
      'prompt_count': instance.promptCount,
      'response_count': instance.responseCount,
      'memory_count': instance.memoryCount,
      'tag_count': instance.tagCount,
      'status': instance.status,
    };

_VirtualFile _$VirtualFileFromJson(Map<String, dynamic> json) => _VirtualFile(
  path: json['path'] as String,
  bucket: json['bucket'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  tags: (json['tags'] as List<dynamic>).map((e) => e as String).toList(),
  status: json['status'] as String,
);

Map<String, dynamic> _$VirtualFileToJson(_VirtualFile instance) =>
    <String, dynamic>{
      'path': instance.path,
      'bucket': instance.bucket,
      'created_at': instance.createdAt.toIso8601String(),
      'tags': instance.tags,
      'status': instance.status,
    };

_AuditEntry _$AuditEntryFromJson(Map<String, dynamic> json) => _AuditEntry(
  type: json['type'] as String,
  detail: json['detail'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
);

Map<String, dynamic> _$AuditEntryToJson(_AuditEntry instance) =>
    <String, dynamic>{
      'type': instance.type,
      'detail': instance.detail,
      'created_at': instance.createdAt.toIso8601String(),
    };
