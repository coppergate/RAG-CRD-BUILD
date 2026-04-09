import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/app_config.dart';
import 'config/service_endpoints.dart';

// Centralized configuration provider for the RAG Explorer app.
final appConfigProvider = NotifierProvider<AppConfigNotifier, AppConfig>(() => AppConfigNotifier());

// Centralized Dio provider that handles TLS verification settings.
final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final dio = Dio();
  
  dio.options.connectTimeout = const Duration(seconds: 10);
  dio.options.receiveTimeout = const Duration(seconds: 30);

  if (config.skipTlsVerification && !kIsWeb) {
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      return client;
    };
  } else if (config.caCertPath != null && !kIsWeb) {
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final SecurityContext context = SecurityContext.defaultContext;
      context.setTrustedCertificates(config.caCertPath!);
      return HttpClient(context: context);
    };
  }

  return dio;
});

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
