import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_config_provider.dart';

class ObservabilityPage extends ConsumerWidget {
  const ObservabilityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final grafanaBaseUrl = '${config.ragAdminApiUrl}/api/grafana';

    return Scaffold(
      appBar: AppBar(title: const Text('Cluster Observability')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Inference Node Monitoring', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ElevatedButton.icon(
                  onPressed: () => launchUrl(Uri.parse('$grafanaBaseUrl/d/rag-inference/inference-nodes?orgId=1&refresh=5s')),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open Full Dashboard'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Real-time GPU/CPU load from inference nodes.', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            
            _buildGrafanaPanel(
              title: 'GPU Utilization',
              url: '$grafanaBaseUrl/d-solo/rag-inference/inference-nodes?orgId=1&panelId=2',
              renderUrl: '$grafanaBaseUrl/render/d-solo/rag-inference/inference-nodes?orgId=1&panelId=2&width=1000&height=500',
            ),
            const SizedBox(height: 16),
            _buildGrafanaPanel(
              title: 'GPU Memory Usage',
              url: '$grafanaBaseUrl/d-solo/rag-inference/inference-nodes?orgId=1&panelId=4',
              renderUrl: '$grafanaBaseUrl/render/d-solo/rag-inference/inference-nodes?orgId=1&panelId=4&width=1000&height=500',
            ),
            const SizedBox(height: 16),
            _buildGrafanaPanel(
              title: 'CPU & System Load',
              url: '$grafanaBaseUrl/d-solo/rag-inference/inference-nodes?orgId=1&panelId=6',
              renderUrl: '$grafanaBaseUrl/render/d-solo/rag-inference/inference-nodes?orgId=1&panelId=6&width=1000&height=500',
            ),
            
            const SizedBox(height: 40),
            const Text('Loki Log Streams', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Log Integration Plan:', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('1. Implement /api/logs/session/{trace_id} in rag-admin-api.'),
                    Text('2. Query Loki via traceID label correlation across all services.'),
                    Text('3. Present unified stream in a LogViewer widget.'),
                    SizedBox(height: 8),
                    Text('Status: Planned (Awaiting discussion)', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.blue)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrafanaPanel({required String title, required String url, required String renderUrl}) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse(url)),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text('View', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          Container(
            height: 250,
            width: double.infinity,
            color: Colors.grey.shade100,
            child: Image.network(
              renderUrl,
              fit: BoxFit.fill,
              errorBuilder: (context, error, stackTrace) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.dashboard, size: 40, color: Colors.blue),
                    const SizedBox(height: 8),
                    Text('Grafana Panel Preview', style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
              ),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
        ],
      ),
    );
  }
}
