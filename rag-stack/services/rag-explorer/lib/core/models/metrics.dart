import 'package:freezed_annotation/freezed_annotation.dart';

part 'metrics.freezed.dart';
part 'metrics.g.dart';

@freezed
abstract class QdrantStats with _$QdrantStats {
  const factory QdrantStats({
    required String status,
    @JsonKey(name: 'points_count') required int pointsCount,
    @JsonKey(name: 'segments_count') required int segmentsCount,
    @JsonKey(name: 'indexed_vectors_count') int? indexedVectorsCount,
    @JsonKey(name: 'payload_schema') Map<String, dynamic>? payloadSchema,
  }) = _QdrantStats;

  factory QdrantStats.fromJson(Map<String, dynamic> json) => _$QdrantStatsFromJson(json);
}

@freezed
abstract class ModelPerformance with _$ModelPerformance {
  const factory ModelPerformance({
    @JsonKey(name: 'model_name') required String modelName,
    required String node,
    @JsonKey(name: 'avg_tokens_per_sec') required double avgTokensPerSec,
    @JsonKey(name: 'avg_latency_ms') required double avgLatencyMs,
    @JsonKey(name: 'total_executions') required int totalExecutions,
  }) = _ModelPerformance;

  factory ModelPerformance.fromJson(Map<String, dynamic> json) => _$ModelPerformanceFromJson(json);
}

@freezed
abstract class SessionHealth with _$SessionHealth {
  const factory SessionHealth({
    @JsonKey(name: 'session_id') required String sessionId,
    @JsonKey(name: 'total_requests') required int totalRequests,
    @JsonKey(name: 'successful_requests') required int successfulRequests,
    @JsonKey(name: 'success_rate') required double successRate,
    @JsonKey(name: 'avg_latency_ms') double? avgLatencyMs,
    @JsonKey(name: 'total_tokens') int? totalTokens,
    required String status, // HEALTHY, DEGRADED, UNHEALTHY
  }) = _SessionHealth;

  factory SessionHealth.fromJson(Map<String, dynamic> json) => _$SessionHealthFromJson(json);
}

@freezed
abstract class VirtualFile with _$VirtualFile {
  const factory VirtualFile({
    required String path,
    required String bucket,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    required List<String> tags,
    required String status, // SYNCED
  }) = _VirtualFile;

  factory VirtualFile.fromJson(Map<String, dynamic> json) => _$VirtualFileFromJson(json);
}

@freezed
abstract class AuditEntry with _$AuditEntry {
  const factory AuditEntry({
    required String type, // RETRIEVAL, MEMORY
    required String detail,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _AuditEntry;

  factory AuditEntry.fromJson(Map<String, dynamic> json) => _$AuditEntryFromJson(json);
}
