import 'dart:convert';

import 'package:flutter/material.dart';

import '../memory_contracts.dart';

class MemoryList extends StatelessWidget {
  final List<MemoryRecord> items;

  const MemoryList({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Text('No memory items found for this session.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(4),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ExpansionTile(
            title: Text(
              item.displayTitle,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _subtitleFor(item),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              if (item.contentPreview != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(item.contentPreview!),
                ),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(
                      item.memoryType.isEmpty ? 'unknown' : item.memoryType,
                    ),
                  ),
                  if (item.pinned) const Chip(label: Text('Pinned')),
                  if (item.salienceHint != null)
                    Chip(
                      label: Text(
                        'Salience ${item.salienceHint!.toStringAsFixed(2)}',
                      ),
                    ),
                  if (item.retentionHint != null)
                    Chip(
                      label: Text(
                        'Retention ${item.retentionHint!.toStringAsFixed(2)}',
                      ),
                    ),
                  if (item.createdAt != null)
                    Chip(
                      label: Text(
                        item.createdAt!.toIso8601String().split('T').first,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _buildDetailRow('Memory ID', item.memoryId?.toString() ?? 'n/a'),
              if (item.status != null) _buildDetailRow('Status', item.status!),
              if (item.salience != null)
                _buildDetailRow('Salience', item.salience!.toStringAsFixed(2)),
              if (item.retentionScore != null)
                _buildDetailRow(
                  'Retention score',
                  item.retentionScore!.toStringAsFixed(2),
                ),
              if (item.expiresAt != null)
                _buildDetailRow('Expires', item.expiresAt!.toIso8601String()),
              if (item.projectId != null)
                _buildDetailRow('Project ID', item.projectId.toString()),
              if (item.userId != null) _buildDetailRow('User ID', item.userId!),
              if (item.metadata.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Metadata',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(item.metadata),
                  ),
                ),
              ],
              if (item.sourceRefs.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Source refs',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 4),
                ...item.sourceRefs.map(
                  (ref) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${ref.sourceKind} / ${ref.sourceId} / ${ref.relationType}${ref.weight == 0.0 ? '' : ' / ${ref.weight.toStringAsFixed(2)}'}',
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _subtitleFor(MemoryRecord item) {
    final parts = <String>[
      if (item.memoryType.isNotEmpty) item.memoryType,
      if (item.salienceHint != null)
        'salience ${item.salienceHint!.toStringAsFixed(2)}',
      if (item.retentionHint != null)
        'retention ${item.retentionHint!.toStringAsFixed(2)}',
    ];
    if (parts.isEmpty) {
      return item.contentPreview ?? 'Memory record';
    }
    return parts.join(' | ');
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
