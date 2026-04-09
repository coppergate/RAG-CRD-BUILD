import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_config_provider.dart';

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
            label: 'RAG Admin API (Base Gateway)',
            value: config.ragAdminApiUrl,
            onChanged: (val) => ref.read(appConfigProvider.notifier).updateRagAdminApi(val),
          ),
          _buildTextField(
            label: 'LLM Gateway',
            value: config.llmGatewayUrl,
            onChanged: (val) => ref.read(appConfigProvider.notifier).update(config.copyWith(llmGatewayUrl: val)),
          ),
          _buildTextField(
            label: 'RAG Ingestion',
            value: config.ragIngestionUrl,
            onChanged: (val) => ref.read(appConfigProvider.notifier).update(config.copyWith(ragIngestionUrl: val)),
          ),
          _buildTextField(
            label: 'DB Adapter',
            value: config.dbAdapterUrl,
            onChanged: (val) => ref.read(appConfigProvider.notifier).update(config.copyWith(dbAdapterUrl: val)),
          ),
          _buildTextField(
            label: 'Object Store Mgr',
            value: config.objectStoreMgrUrl,
            onChanged: (val) => ref.read(appConfigProvider.notifier).update(config.copyWith(objectStoreMgrUrl: val)),
          ),
          _buildTextField(
            label: 'Qdrant Adapter',
            value: config.qdrantAdapterUrl,
            onChanged: (val) => ref.read(appConfigProvider.notifier).update(config.copyWith(qdrantAdapterUrl: val)),
          ),
          _buildTextField(
            label: 'Memory Controller',
            value: config.memoryControllerUrl,
            onChanged: (val) => ref.read(appConfigProvider.notifier).update(config.copyWith(memoryControllerUrl: val)),
          ),
          _buildTextField(
            label: 'Grafana',
            value: config.grafanaUrl,
            onChanged: (val) => ref.read(appConfigProvider.notifier).update(config.copyWith(grafanaUrl: val)),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('TLS Configuration'),
          SwitchListTile(
            title: const Text('Skip TLS Verification (Dev only)'),
            value: config.skipTlsVerification,
            onChanged: (val) => ref.read(appConfigProvider.notifier).update(config.copyWith(skipTlsVerification: val)),
          ),
          _buildTextField(
            label: 'CA Certificate Path',
            value: config.caCertPath ?? '',
            onChanged: (val) => ref.read(appConfigProvider.notifier).update(config.copyWith(caCertPath: val)),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Appearance'),
          SwitchListTile(
            title: const Text('Dark Mode'),
            value: config.darkMode,
            onChanged: (val) => ref.read(appConfigProvider.notifier).update(config.copyWith(darkMode: val)),
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
