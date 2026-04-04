// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AppConfig _$AppConfigFromJson(Map<String, dynamic> json) => _AppConfig(
  llmGatewayUrl: json['llmGatewayUrl'] as String,
  ragIngestionUrl: json['ragIngestionUrl'] as String,
  objectStoreMgrUrl: json['objectStoreMgrUrl'] as String,
  dbAdapterUrl: json['dbAdapterUrl'] as String,
  qdrantAdapterUrl: json['qdrantAdapterUrl'] as String,
  memoryControllerUrl: json['memoryControllerUrl'] as String,
  grafanaUrl: json['grafanaUrl'] as String,
  ragAdminApiUrl: json['ragAdminApiUrl'] as String,
  skipTlsVerification: json['skipTlsVerification'] as bool? ?? true,
  caCertPath: json['caCertPath'] as String?,
  darkMode: json['darkMode'] as bool? ?? true,
  availableModels:
      (json['availableModels'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const ['llama3.1:latest', 'granite3.1-dense:8b'],
  memoryExplorerEnabled: json['memoryExplorerEnabled'] as bool? ?? true,
  modelComparisonEnabled: json['modelComparisonEnabled'] as bool? ?? true,
  promptTimeoutSeconds: (json['promptTimeoutSeconds'] as num?)?.toInt() ?? 60,
);

Map<String, dynamic> _$AppConfigToJson(_AppConfig instance) =>
    <String, dynamic>{
      'llmGatewayUrl': instance.llmGatewayUrl,
      'ragIngestionUrl': instance.ragIngestionUrl,
      'objectStoreMgrUrl': instance.objectStoreMgrUrl,
      'dbAdapterUrl': instance.dbAdapterUrl,
      'qdrantAdapterUrl': instance.qdrantAdapterUrl,
      'memoryControllerUrl': instance.memoryControllerUrl,
      'grafanaUrl': instance.grafanaUrl,
      'ragAdminApiUrl': instance.ragAdminApiUrl,
      'skipTlsVerification': instance.skipTlsVerification,
      'caCertPath': instance.caCertPath,
      'darkMode': instance.darkMode,
      'availableModels': instance.availableModels,
      'memoryExplorerEnabled': instance.memoryExplorerEnabled,
      'modelComparisonEnabled': instance.modelComparisonEnabled,
      'promptTimeoutSeconds': instance.promptTimeoutSeconds,
    };
