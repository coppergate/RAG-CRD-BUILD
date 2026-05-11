// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AppConfig _$AppConfigFromJson(Map<String, dynamic> json) => _AppConfig(
  ragAdminApiUrl:
      json['ragAdminApiUrl'] as String? ??
      'https://rag-admin-api.rag.hierocracy.home',
  skipTlsVerification: json['skipTlsVerification'] as bool? ?? true,
  caCertPath: json['caCertPath'] as String?,
  defaultBucketName:
      json['defaultBucketName'] as String? ?? 'rag-codebase-bucket',
  darkMode: json['darkMode'] as bool? ?? true,
  availableModels:
      (json['availableModels'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const ['llama3.1:latest', 'granite3.1-dense:8b'],
  memoryExplorerEnabled: json['memoryExplorerEnabled'] as bool? ?? true,
  modelComparisonEnabled: json['modelComparisonEnabled'] as bool? ?? true,
  promptTimeoutSeconds: (json['promptTimeoutSeconds'] as num?)?.toInt() ?? 120,
);

Map<String, dynamic> _$AppConfigToJson(_AppConfig instance) =>
    <String, dynamic>{
      'ragAdminApiUrl': instance.ragAdminApiUrl,
      'skipTlsVerification': instance.skipTlsVerification,
      'caCertPath': instance.caCertPath,
      'defaultBucketName': instance.defaultBucketName,
      'darkMode': instance.darkMode,
      'availableModels': instance.availableModels,
      'memoryExplorerEnabled': instance.memoryExplorerEnabled,
      'modelComparisonEnabled': instance.modelComparisonEnabled,
      'promptTimeoutSeconds': instance.promptTimeoutSeconds,
    };
