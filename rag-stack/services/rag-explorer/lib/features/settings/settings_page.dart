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
          _buildReadOnlyField(label: 'Derived Chat URL', value: config.chatUrl),
          _buildReadOnlyField(label: 'Derived Ingest URL', value: config.ingestUrl),
          _buildReadOnlyField(label: 'Derived DB URL', value: config.dbUrl),
          _buildReadOnlyField(label: 'Derived S3 URL', value: config.s3Url),
          _buildReadOnlyField(label: 'Derived Qdrant URL', value: config.qdrantUrl),
          _buildReadOnlyField(label: 'Derived Memory URL', value: config.memoryUrl),
          _buildReadOnlyField(label: 'Derived Grafana URL', value: config.grafanaUrl),
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

  Widget _buildReadOnlyField({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextFormField(
        initialValue: value,
        readOnly: true,
        enabled: false,
        decoration: InputDecoration(
          labelText: label,
          border: const UnderlineInputBorder(),
          filled: true,
          fillColor: Colors.grey.shade100,
        ),
      ),
    );
  }
}
