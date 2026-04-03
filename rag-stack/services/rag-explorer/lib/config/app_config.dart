import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_config.freezed.dart';
part 'app_config.g.dart';

@freezed
abstract class AppConfig with _$AppConfig {
  const factory AppConfig({
    required String llmGatewayUrl,
    required String ragIngestionUrl,
    required String objectStoreMgrUrl,
    required String dbAdapterUrl,
    required String qdrantAdapterUrl,
    required String memoryControllerUrl,
    required String grafanaUrl,
    required String ragAdminApiUrl,
    @Default(true) bool skipTlsVerification,
    String? caCertPath,
    @Default(false) bool darkMode,
    @Default(['llama3.1', 'granite3.1-dense:8b']) List<String> availableModels,
    @Default(true) bool memoryExplorerEnabled,
    @Default(true) bool modelComparisonEnabled,
  }) = _AppConfig;

  factory AppConfig.fromJson(Map<String, dynamic> json) => _$AppConfigFromJson(json);
}
