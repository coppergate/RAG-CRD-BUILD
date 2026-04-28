import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/service_endpoints.dart';
import '../../core/api_client.dart';
import '../../core/models/metrics.dart';
import '../../core/models/session.dart';
import '../../app_config_provider.dart';

class TimescalePage extends ConsumerStatefulWidget {
  const TimescalePage({super.key});

  @override
  ConsumerState<TimescalePage> createState() => _TimescalePageState();
}

class _TimescalePageState extends ConsumerState<TimescalePage> {
  late Future<List<Session>> _sessionsFuture;
  Session? _selectedSession;
  SessionHealth? _currentHealth;
  List<AuditEntry>? _auditLogs;
  bool _loadingDetails = false;

  @override
  void initState() {
    super.initState();
    _sessionsFuture = _fetchSessions();
  }

  Future<List<Session>> _fetchSessions() async {
    final config = ref.read(appConfigProvider);
    final client = ApiClient(config);
    final response = await client.get('${ServiceEndpoints.dbAdapter}/sessions');
    return (response.data as List).map((e) => Session.fromJson(e)).toList();
  }

  Future<void> _loadSessionDetails(Session session) async {
    setState(() {
      _selectedSession = session;
      _loadingDetails = true;
    });

    try {
      final config = ref.read(appConfigProvider);
      final client = ApiClient(config);
      
      final healthResp = await client.get('${ServiceEndpoints.dbAdapter}/sessions/${session.id}/health');
      final auditResp = await client.get('${ServiceEndpoints.dbAdapter}/audit/sessions/${session.id}');
      
      setState(() {
        _currentHealth = SessionHealth.fromJson(healthResp.data);
        _auditLogs = (auditResp.data as List).map((e) => AuditEntry.fromJson(e)).toList();
        _loadingDetails = false;
      });
    } catch (e) {
      setState(() => _loadingDetails = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading details: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TimescaleDB Explorer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.merge_type),
            onPressed: _showMergeDialog,
            tooltip: 'Maintenance: Merge Tags',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _sessionsFuture = _fetchSessions()),
          ),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 300,
            child: _buildSessionList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _buildSessionDetails(),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionList() {
    return FutureBuilder<List<Session>>(
      future: _sessionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        
        final sessions = snapshot.data!;
        return ListView.builder(
          itemCount: sessions.length,
          itemBuilder: (context, index) {
            final s = sessions[index];
            return ListTile(
              selected: _selectedSession?.id == s.id,
              title: Text('Session ${s.id.substring(0, 8)}'),
              subtitle: Text(s.createdAt.toString().split(' ')[0]),
              onTap: () => _loadSessionDetails(s),
            );
          },
        );
      },
    );
  }

  Widget _buildSessionDetails() {
    if (_selectedSession == null) {
      return const Center(child: Text('Select a session to view health and audit logs'));
    }
    if (_loadingDetails) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHealthCard(),
          const SizedBox(height: 24),
          const Text('Audit Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildAuditTable(),
        ],
      ),
    );
  }

  Widget _buildHealthCard() {
    if (_currentHealth == null) return const SizedBox();
    
    final h = _currentHealth!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Session Health', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Chip(
                  label: Text(h.status),
                  backgroundColor: _getStatusColor(h.status).withValues(alpha: 0.1),
                  labelStyle: TextStyle(color: _getStatusColor(h.status), fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                _buildHealthStat('Success Rate', '${(h.successRate * 100).toStringAsFixed(1)}%'),
                _buildHealthStat('Avg Latency', '${h.avgLatencyMs?.toStringAsFixed(0) ?? "N/A"} ms'),
                _buildHealthStat('Total Tokens', '${h.totalTokens ?? 0}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthStat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildAuditTable() {
    if (_auditLogs == null || _auditLogs!.isEmpty) {
      return const Text('No audit events found.');
    }

    return Table(
      border: TableBorder.all(color: Colors.grey.shade300),
      columnWidths: const {
        0: FixedColumnWidth(100),
        1: FlexColumnWidth(),
        2: FixedColumnWidth(150),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: const [
            Padding(padding: EdgeInsets.all(8), child: Text('Type', style: TextStyle(fontWeight: FontWeight.bold))),
            Padding(padding: EdgeInsets.all(8), child: Text('Detail', style: TextStyle(fontWeight: FontWeight.bold))),
            Padding(padding: EdgeInsets.all(8), child: Text('Timestamp', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        ..._auditLogs!.map((log) => TableRow(
          children: [
            Padding(padding: const EdgeInsets.all(8), child: Text(log.type)),
            Padding(padding: const EdgeInsets.all(8), child: Text(log.detail)),
            Padding(padding: const EdgeInsets.all(8), child: Text(log.createdAt.toLocal().toString().split('.')[0])),
          ],
        )),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'HEALTHY': return Colors.green;
      case 'DEGRADED': return Colors.orange;
      case 'UNHEALTHY': return Colors.red;
      default: return Colors.grey;
    }
  }

  void _showMergeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge Tags (Maintenance)'),
        content: const Text('This will unify multiple tags into a single target and sync the vector store. This action is irreversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              // Implementation of merge logic would go here
              Navigator.pop(context);
            },
            child: const Text('Merge'),
          ),
        ],
      ),
    );
  }
}
