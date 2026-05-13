import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_config_provider.dart';
import '../../core/services/log_service.dart';

class ObservabilityPage extends ConsumerStatefulWidget {
  const ObservabilityPage({super.key});

  @override
  ConsumerState<ObservabilityPage> createState() => _ObservabilityPageState();
}

class _ObservabilityPageState extends ConsumerState<ObservabilityPage> {
  @override
  void initState() {
    super.initState();
    ref.read(logProvider.notifier).info('Opening observability dashboard');
  }

  @override
  Widget build(BuildContext context) {
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
                const Text(
                  'Inference Node Monitoring',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(
                      '$grafanaBaseUrl/d/rag-inference/inference-nodes?orgId=1&refresh=5s',
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open Full Dashboard'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Real-time GPU/CPU load from inference nodes.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            _GrafanaPanelCard(
              title: 'GPU Utilization',
              url:
                  '$grafanaBaseUrl/d-solo/rag-inference/inference-nodes?orgId=1&panelId=2',
              renderUrl:
                  '$grafanaBaseUrl/render/d-solo/rag-inference/inference-nodes?orgId=1&panelId=2&scale=2&width={width}&height=500&from=now-1h&to=now&_t=${DateTime.now().millisecondsSinceEpoch}',
            ),
            const SizedBox(height: 16),
            _GrafanaPanelCard(
              title: 'GPU Memory Usage',
              url:
                  '$grafanaBaseUrl/d-solo/rag-inference/inference-nodes?orgId=1&panelId=4',
              renderUrl:
                  '$grafanaBaseUrl/render/d-solo/rag-inference/inference-nodes?orgId=1&panelId=4&scale=2&width={width}&height=500&from=now-1h&to=now&_t=${DateTime.now().millisecondsSinceEpoch}',
            ),
            const SizedBox(height: 16),
            _GrafanaPanelCard(
              title: 'CPU & System Load',
              url:
                  '$grafanaBaseUrl/d-solo/rag-inference/inference-nodes?orgId=1&panelId=6',
              renderUrl:
                  '$grafanaBaseUrl/render/d-solo/rag-inference/inference-nodes?orgId=1&panelId=6&scale=2&width={width}&height=500&from=now-1h&to=now&_t=${DateTime.now().millisecondsSinceEpoch}',
            ),
            const SizedBox(height: 40),
            const Text(
              'Loki Log Streams',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Log Integration Plan:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '1. Implement /api/logs/session/{trace_id} in rag-admin-api.',
                    ),
                    const Text(
                      '2. Query Loki via traceID label correlation across all services.',
                    ),
                    const Text(
                      '3. Present unified stream in a LogViewer widget.',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Status: Planned (Awaiting discussion)',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GrafanaPanelCard extends ConsumerStatefulWidget {
  final String title;
  final String url;
  final String renderUrl;

  const _GrafanaPanelCard({
    required this.title,
    required this.url,
    required this.renderUrl,
  });

  @override
  ConsumerState<_GrafanaPanelCard> createState() => _GrafanaPanelCardState();
}

class _GrafanaPanelCardState extends ConsumerState<_GrafanaPanelCard> {
  bool _isLoaded = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    ref
        .read(logProvider.notifier)
        .debug('Loading Grafana panel: ${widget.title}');
  }

  void _markLoaded() {
    if (_isLoaded) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isLoaded) {
        return;
      }
      setState(() {
        _isLoaded = true;
      });
      ref
          .read(logProvider.notifier)
          .info('Grafana panel loaded: ${widget.title}');
    });
  }

  @override
  Widget build(BuildContext context) {
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
                Text(
                  widget.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse(widget.url)),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text('View', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth.toInt();
              final dynamicRenderUrl = widget.renderUrl.replaceAll(
                '{width}',
                (width * 2).toString(),
              );

              return SizedBox(
                height: 250,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: Colors.grey.shade100),
                    Image.network(
                      dynamicRenderUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) {
                          _markLoaded();
                          return child;
                        }
                        return const SizedBox.shrink();
                      },
                      errorBuilder: (context, error, stackTrace) {
                        if (!_hasError) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && !_hasError) {
                              setState(() => _hasError = true);
                              ref
                                  .read(logProvider.notifier)
                                  .error(
                                    'Grafana panel failed: ${widget.title} ($error)',
                                  );
                            }
                          });
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    if (!_isLoaded && !_hasError)
                      Container(
                        color: Colors.black.withValues(alpha: 0.02),
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(height: 12),
                              Text('Loading panel...'),
                            ],
                          ),
                        ),
                      ),
                    if (_hasError)
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.warning_amber_outlined,
                              size: 40,
                              color: Colors.orange,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Grafana panel preview unavailable',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
