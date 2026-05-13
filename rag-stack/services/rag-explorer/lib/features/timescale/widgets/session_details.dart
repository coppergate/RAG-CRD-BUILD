import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/session.dart';
import '../../../core/models/metrics.dart';

class SessionDetails extends StatelessWidget {
  final Session session;
  final SessionHealth? health;
  final List<AuditEntry>? auditLogs;
  final bool isLoading;
  final bool isDarkMode;

  const SessionDetails({
    super.key,
    required this.session,
    this.health,
    this.auditLogs,
    required this.isLoading,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHealthCard(context),
          const SizedBox(height: 24),
          _buildTagsSection(context),
          const SizedBox(height: 24),
          const Text(
            'Audit Log',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildAuditTable(context),
        ],
      ),
    );
  }

  Widget _buildHealthCard(BuildContext context) {
    if (health == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No health data.'),
        ),
      );
    }

    final h = health!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Session Health',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Chip(
                  label: Text(h.status),
                  backgroundColor: _getStatusColor(
                    h.status,
                  ).withValues(alpha: 0.1),
                  labelStyle: TextStyle(
                    color: _getStatusColor(h.status),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                _buildHealthStat(
                  'Success Rate',
                  '${(h.successRate * 100).toStringAsFixed(1)}%',
                ),
                _buildHealthStat(
                  'Avg Latency',
                  '${h.avgLatencyMs?.toStringAsFixed(0) ?? "N/A"} ms',
                ),
                _buildHealthStat('Total Tokens', '${h.totalTokens ?? 0}'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildHealthStat('Prompts', '${h.promptCount ?? 0}'),
                _buildHealthStat('Responses', '${h.responseCount ?? 0}'),
                _buildHealthStat('Memory Items', '${h.memoryCount ?? 0}'),
                _buildHealthStat('Tags', '${h.tagCount ?? 0}'),
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
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildTagsSection(BuildContext context) {
    final tags = session.tags ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Session Tags',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (tags.isEmpty)
          const Text(
            'No tags associated with this session.',
            style: TextStyle(fontStyle: FontStyle.italic),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags
                .map(
                  (t) => ActionChip(
                    avatar: const Icon(Icons.tag, size: 16),
                    label: Text(t.name),
                    onPressed: () =>
                        context.go('/s3?tag=${Uri.encodeComponent(t.name)}'),
                    tooltip: 'View files in S3 Browser for this tag',
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  Widget _buildAuditTable(BuildContext context) {
    if (auditLogs == null || auditLogs!.isEmpty) {
      return const Text('No audit events found.');
    }

    final theme = Theme.of(context);
    final headerBackground = isDarkMode
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainerHighest;
    final headerForeground = theme.colorScheme.onSurface;
    final borderColor = isDarkMode
        ? theme.colorScheme.outlineVariant
        : Colors.grey.shade300;

    return Table(
      border: TableBorder.all(color: borderColor),
      columnWidths: const {
        0: FixedColumnWidth(100),
        1: FlexColumnWidth(),
        2: FixedColumnWidth(150),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: headerBackground),
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Type',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: headerForeground,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Detail',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: headerForeground,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Timestamp',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: headerForeground,
                ),
              ),
            ),
          ],
        ),
        ...auditLogs!.map(
          (log) => TableRow(
            children: [
              Padding(padding: const EdgeInsets.all(8), child: Text(log.type)),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(log.detail),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(log.createdAt.toLocal().toString().split('.')[0]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'HEALTHY':
        return Colors.green;
      case 'DEGRADED':
        return Colors.orange;
      case 'UNHEALTHY':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
