import 'package:flutter/material.dart';
import '../../../core/models/metrics.dart';

class AuditTable extends StatelessWidget {
  final List<AuditEntry> entries;
  final bool isLoading;

  const AuditTable({
    super.key,
    required this.entries,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (entries.isEmpty) {
      return const Center(child: Text('No audit logs for this session.'));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Time')),
          DataColumn(label: Text('Type')),
          DataColumn(label: Text('Details')),
        ],
        rows: entries.map((e) => DataRow(
          cells: [
            DataCell(Text(e.createdAt.toLocal().toString().split(' ')[1].split('.')[0])),
            DataCell(Text(e.type)),
            DataCell(Text(e.detail)),
          ],
        )).toList(),
      ),
    );
  }
}
