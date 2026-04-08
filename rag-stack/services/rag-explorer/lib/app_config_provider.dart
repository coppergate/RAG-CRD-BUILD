import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/app_config.dart';
import 'config/service_endpoints.dart';

// Centralized configuration provider for the RAG Explorer app.
final appConfigProvider = NotifierProvider<AppConfigNotifier, AppConfig>(() => AppConfigNotifier());

class AppConfigNotifier extends Notifier<AppConfig> {
  @override
  AppConfig build() {
    return const AppConfig(
      llmGatewayUrl: ServiceEndpoints.llmGateway,
      ragIngestionUrl: ServiceEndpoints.ragIngestion,
      objectStoreMgrUrl: ServiceEndpoints.objectStoreMgr,
      dbAdapterUrl: ServiceEndpoints.dbAdapter,
      qdrantAdapterUrl: ServiceEndpoints.qdrantAdapter,
      memoryControllerUrl: ServiceEndpoints.memoryController,
      grafanaUrl: ServiceEndpoints.grafana,
      ragAdminApiUrl: ServiceEndpoints.ragAdminApi,
    );
  }

  void update(AppConfig config) {
    state = config;
  }

  void updateRagAdminApi(String url) {
    state = state.copyWith(
      ragAdminApiUrl: url,
      llmGatewayUrl: '$url/api/chat',
      ragIngestionUrl: '$url/api/ingest',
      objectStoreMgrUrl: '$url/api/s3',
      dbAdapterUrl: '$url/api/db',
      qdrantAdapterUrl: '$url/api/qdrant',
      memoryControllerUrl: '$url/api/memory',
    );
  }
}
