import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../config/service_endpoints.dart';
import '../../core/models/metrics.dart';
import '../../core/api_client.dart';
import '../../app_config_provider.dart';
import 'package:provider/provider.dart';

class QdrantPage extends StatefulWidget {
  const QdrantPage({super.key});

  @override
  State<QdrantPage> createState() => _QdrantPageState();
}

class _QdrantPageState extends State<QdrantPage> {
  late Future<List<Map<String, dynamic>>> _collectionsFuture;

  @override
  void initState() {
    super.initState();
    _collectionsFuture = _fetchCollections();
  }

  Future<List<Map<String, dynamic>>> _fetchCollections() async {
    final config = context.read<AppConfigProvider>().config;
    final client = ApiClient(config);
    
    final response = await client.get('${ServiceEndpoints.qdrantAdapter}/collections');
    final collections = (response.data['result']['collections'] as List);
    
    List<Map<String, dynamic>> details = [];
    for (var coll in collections) {
      final name = coll['name'];
      final statsResp = await client.get('${ServiceEndpoints.qdrantAdapter}/collections/$name/stats');
      details.add({
        'name': name,
        'stats': QdrantStats.fromJson(statsResp.data),
      });
    }
    return details;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Qdrant Vector Explorer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _collectionsFuture = _fetchCollections()),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _collectionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          
          final collections = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: collections.length,
            itemBuilder: (context, index) {
              final coll = collections[index];
              final stats = coll['stats'] as QdrantStats;
              
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(coll['name'], style: Theme.of(context).textTheme.titleLarge),
                          Chip(
                            label: Text(stats.status),
                            backgroundColor: stats.status == 'green' ? Colors.green.shade100 : Colors.orange.shade100,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildStatRow('Points', stats.pointsCount.toString(), Icons.grain),
                      _buildStatRow('Segments', stats.segmentsCount.toString(), Icons.segment),
                      _buildStatRow('Indexed Vectors', (stats.indexedVectorsCount ?? 0).toString(), Icons.speed),
                      const SizedBox(height: 16),
                      const Text('Vector Density', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: stats.pointsCount > 0 ? (stats.indexedVectorsCount ?? 0) / stats.pointsCount : 0,
                        backgroundColor: Colors.grey.shade200,
                        color: Colors.blue,
                        minHeight: 10,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${((stats.indexedVectorsCount ?? 0) / (stats.pointsCount > 0 ? stats.pointsCount : 1) * 100).toStringAsFixed(1)}% Indexed',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }
}
