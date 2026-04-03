import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_config.dart';
import '../../config/service_endpoints.dart';

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
    );
  }

  void update(AppConfig config) {
    state = config;
  }
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('Service Endpoints'),
          _buildTextField(
            label: 'LLM Gateway',
            value: config.llmGatewayUrl,
            onChanged: (val) => ref.read(appConfigProvider.notifier).state = config.copyWith(llmGatewayUrl: val),
          ),
          _buildTextField(
            label: 'RAG Ingestion',
            value: config.ragIngestionUrl,
            onChanged: (val) => ref.read(appConfigProvider.notifier).state = config.copyWith(ragIngestionUrl: val),
          ),
          _buildTextField(
            label: 'DB Adapter',
            value: config.dbAdapterUrl,
            onChanged: (val) => ref.read(appConfigProvider.notifier).state = config.copyWith(dbAdapterUrl: val),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('TLS Configuration'),
          SwitchListTile(
            title: const Text('Skip TLS Verification (Dev only)'),
            value: config.skipTlsVerification,
            onChanged: (val) => ref.read(appConfigProvider.notifier).state = config.copyWith(skipTlsVerification: val),
          ),
          _buildTextField(
            label: 'CA Certificate Path',
            value: config.caCertPath ?? '',
            onChanged: (val) => ref.read(appConfigProvider.notifier).state = config.copyWith(caCertPath: val),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Appearance'),
          SwitchListTile(
            title: const Text('Dark Mode'),
            value: config.darkMode,
            onChanged: (val) => ref.read(appConfigProvider.notifier).state = config.copyWith(darkMode: val),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTextField({required String label, required String value, required Function(String) onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
