import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_config.freezed.dart';
part 'app_config.g.dart';

@freezed
abstract class AppConfig with _$AppConfig {
  const AppConfig._(); // enables custom getters

  const factory AppConfig({
    @Default('https://rag-admin-api.rag.hierocracy.home') String ragAdminApiUrl,
    @Default(true) bool skipTlsVerification,
    String? caCertPath,
    @Default('rag-codebase-bucket') String defaultBucketName,
    @Default(true) bool darkMode,
    @Default(['granite3.1-dense:8b', 'qwen3:32b', 'qwen2.5:32b', 'llama3.2:3b', 'llama3.1'])
    List<String> availableModels,
    @Default(['all-minilm:l6-v2', 'mxbai-embed-large', 'nomic-embed-text'])
    List<String> availableEmbeddingModels,
    @Default(true) bool memoryExplorerEnabled,
    @Default(true) bool modelComparisonEnabled,
    @Default(120) int promptTimeoutSeconds,
    @Default(10) int connectTimeoutSeconds,
    @Default(30) int receiveTimeoutSeconds,
  }) = _AppConfig;

  factory AppConfig.fromJson(Map<String, dynamic> json) =>
      _$AppConfigFromJson(json);

  String get chatUrl => '$ragAdminApiUrl/api/chat';
  String get ingestUrl => '$ragAdminApiUrl/api/ingest';
  String get s3Url => '$ragAdminApiUrl/api/s3';
  String get dbUrl => '$ragAdminApiUrl/api/db';
  String get qdrantUrl => '$ragAdminApiUrl/api/qdrant';
  String get memoryUrl => '$ragAdminApiUrl/api/memory';
  String get behaviorUrl => '$ragAdminApiUrl/api/behavior';
  String get grafanaUrl => '$ragAdminApiUrl/api/grafana';
  String get qdrantDirectUrl => '$ragAdminApiUrl/api/qdrant-direct';
}
