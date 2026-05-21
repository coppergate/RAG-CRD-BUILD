import 'package:flutter/material.dart';
import '../../../core/models/metrics.dart';

class CollectionCard extends StatelessWidget {
  final String name;
  final QdrantStats stats;

  const CollectionCard({super.key, required this.name, required this.stats});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final statusColor = stats.status == 'green'
        ? Colors.green
        : Colors.orange;
    final chipBackground = isDarkMode
        ? statusColor.shade900.withValues(alpha: 0.5)
        : statusColor.shade100;
    final chipBorder = isDarkMode
        ? statusColor.shade300.withValues(alpha: 0.8)
        : statusColor.shade300;
    final chipTextColor = isDarkMode ? Colors.white : statusColor.shade900;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(name, style: Theme.of(context).textTheme.titleLarge),
                Chip(
                  label: Text(
                    stats.status,
                    style: TextStyle(
                      color: chipTextColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  backgroundColor: chipBackground,
                  side: BorderSide(color: chipBorder),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatRow('Points', stats.pointsCount.toString(), Icons.grain),
            _buildStatRow(
              'Segments',
              stats.segmentsCount.toString(),
              Icons.segment,
            ),
            _buildStatRow(
              'Indexed Vectors',
              (stats.indexedVectorsCount ?? 0).toString(),
              Icons.speed,
            ),
            const SizedBox(height: 16),
            const Text(
              'Vector Density',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: stats.pointsCount > 0
                  ? (stats.indexedVectorsCount ?? 0) / stats.pointsCount
                  : 0,
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
