import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/service_endpoints.dart';
import '../../core/api_client.dart';
import '../../core/models/metrics.dart';

class ModelsPage extends StatefulWidget {
  const ModelsPage({super.key});

  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends State<ModelsPage> {
  late Future<List<ModelPerformance>> _metricsFuture;

  @override
  void initState() {
    super.initState();
    _metricsFuture = _fetchMetrics();
  }

  Future<List<ModelPerformance>> _fetchMetrics() async {
    final config = context.read<AppConfigProvider>().config;
    final client = ApiClient(config);
    final response = await client.get('${ServiceEndpoints.dbAdapter}/metrics/summary');
    return (response.data as List).map((e) => ModelPerformance.fromJson(e)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Performance Comparison'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _metricsFuture = _fetchMetrics()),
          ),
        ],
      ),
      body: FutureBuilder<List<ModelPerformance>>(
        future: _metricsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          
          final metrics = snapshot.data!;
          if (metrics.isEmpty) {
            return const Center(child: Text('No performance metrics available yet.'));
          }

          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Model')),
                  DataColumn(label: Text('Node')),
                  DataColumn(label: Text('Efficiency (tok/s)'), numeric: true),
                  DataColumn(label: Text('Latency (ms)'), numeric: true),
                  DataColumn(label: Text('Executions'), numeric: true),
                ],
                rows: metrics.map((m) => DataRow(
                  cells: [
                    DataCell(Text(m.modelName, style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text(m.node)),
                    DataCell(Text(m.avgTokensPerSec.toStringAsFixed(2), 
                      style: TextStyle(color: _getEfficiencyColor(m.avgTokensPerSec), fontWeight: FontWeight.bold))),
                    DataCell(Text(m.avgLatencyMs.toStringAsFixed(0))),
                    DataCell(Text(m.totalExecutions.toString())),
                  ],
                )).toList(),
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getEfficiencyColor(double tps) {
    if (tps >= 50) return Colors.green;
    if (tps >= 20) return Colors.blue;
    if (tps >= 10) return Colors.orange;
    return Colors.red;
  }
}
