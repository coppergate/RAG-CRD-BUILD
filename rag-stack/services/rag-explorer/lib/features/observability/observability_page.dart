import 'package:flutter/material.dart';
import '../../config/service_endpoints.dart';

class ObservabilityPage extends StatelessWidget {
  const ObservabilityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cluster Observability')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Inference Node Monitoring', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Real-time GPU/CPU load from inference nodes.', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            
            _buildGrafanaPanel(
              title: 'GPU Utilization',
              url: '${ServiceEndpoints.grafana}/d-solo/rag-inference/inference-nodes?orgId=1&panelId=2',
            ),
            const SizedBox(height: 16),
            _buildGrafanaPanel(
              title: 'GPU Memory Usage',
              url: '${ServiceEndpoints.grafana}/d-solo/rag-inference/inference-nodes?orgId=1&panelId=4',
            ),
            const SizedBox(height: 16),
            _buildGrafanaPanel(
              title: 'CPU & System Load',
              url: '${ServiceEndpoints.grafana}/d-solo/rag-inference/inference-nodes?orgId=1&panelId=6',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrafanaPanel({required String title, required String url}) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Container(
            height: 300,
            width: double.infinity,
            color: Colors.grey.shade100,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.dashboard, size: 48, color: Colors.blue),
                  const SizedBox(height: 8),
                  Text('Grafana Panel Proxy', style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(url, style: const TextStyle(fontSize: 10, color: Colors.blue), textAlign: TextAlign.center),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
