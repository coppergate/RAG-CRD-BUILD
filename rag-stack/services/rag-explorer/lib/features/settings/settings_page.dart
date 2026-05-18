import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_config_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final darkMode = config.darkMode;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('Service Endpoints'),
          _buildTextField(
            darkMode: darkMode,
            label: 'RAG Admin API (Base Gateway)',
            value: config.ragAdminApiUrl,
            onChanged: (val) =>
                ref.read(appConfigProvider.notifier).updateRagAdminApi(val),
          ),
          _buildReadOnlyField(
            darkMode: darkMode,
            label: 'Derived Chat URL',
            value: config.chatUrl,
          ),
          _buildReadOnlyField(
            darkMode: darkMode,
            label: 'Derived Ingest URL',
            value: config.ingestUrl,
          ),
          _buildReadOnlyField(
            darkMode: darkMode,
            label: 'Derived DB URL',
            value: config.dbUrl,
          ),
          _buildReadOnlyField(
            darkMode: darkMode,
            label: 'Derived S3 URL',
            value: config.s3Url,
          ),
          _buildReadOnlyField(
            darkMode: darkMode,
            label: 'Derived Qdrant URL',
            value: config.qdrantUrl,
          ),
          _buildReadOnlyField(
            darkMode: darkMode,
            label: 'Derived Memory URL',
            value: config.memoryUrl,
          ),
          _buildReadOnlyField(
            darkMode: darkMode,
            label: 'Derived Grafana URL',
            value: config.grafanaUrl,
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('TLS Configuration'),
          SwitchListTile(
            title: const Text('Skip TLS Verification (Dev only)'),
            value: config.skipTlsVerification,
            onChanged: (val) => ref
                .read(appConfigProvider.notifier)
                .update(config.copyWith(skipTlsVerification: val)),
          ),
          _buildTextField(
            darkMode: darkMode,
            label: 'CA Certificate Path',
            value: config.caCertPath ?? '',
            onChanged: (val) => ref
                .read(appConfigProvider.notifier)
                .update(config.copyWith(caCertPath: val)),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Appearance'),
          SwitchListTile(
            title: const Text('Dark Mode'),
            value: config.darkMode,
            onChanged: (val) => ref
                .read(appConfigProvider.notifier)
                .update(config.copyWith(darkMode: val)),
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

  Widget _buildTextField({
    required bool darkMode,
    required String label,
    required String value,
    required Function(String) onChanged,
  }) {
    final fillColor = darkMode ? Colors.grey.shade900 : Colors.grey.shade50;
    final borderColor = darkMode ? Colors.grey.shade700 : Colors.grey.shade400;
    final focusedColor = darkMode ? Colors.blue.shade300 : Colors.blue.shade700;
    final textColor = darkMode ? Colors.white : Colors.black87;
    final labelColor = darkMode ? Colors.grey.shade300 : Colors.grey.shade700;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        initialValue: value,
        style: TextStyle(color: textColor),
        cursorColor: focusedColor,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: labelColor),
          floatingLabelStyle: TextStyle(color: focusedColor),
          filled: true,
          fillColor: fillColor,
          border: OutlineInputBorder(
            borderSide: BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: focusedColor, width: 2),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildReadOnlyField({
    required bool darkMode,
    required String label,
    required String value,
  }) {
    final fillColor = darkMode ? Colors.grey.shade900 : Colors.grey.shade100;
    final borderColor = darkMode ? Colors.grey.shade700 : Colors.grey.shade300;
    final textColor = darkMode ? Colors.white70 : Colors.black87;
    final labelColor = darkMode ? Colors.grey.shade400 : Colors.grey.shade700;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextFormField(
        initialValue: value,
        readOnly: true,
        style: TextStyle(color: textColor),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: labelColor),
          floatingLabelStyle: TextStyle(color: labelColor),
          filled: true,
          fillColor: fillColor,
          border: OutlineInputBorder(
            borderSide: BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: borderColor),
          ),
          disabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: borderColor),
          ),
        ),
      ),
    );
  }
}
