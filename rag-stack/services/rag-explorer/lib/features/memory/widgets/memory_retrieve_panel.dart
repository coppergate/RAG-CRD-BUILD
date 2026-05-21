import 'package:flutter/material.dart';

import '../memory_contracts.dart';
import '../memory_notifier.dart';

class MemoryRetrievePanel extends StatefulWidget {
  final MemoryState state;
  final Future<void> Function(String) onRetrieve;
  final void Function(int) onLimitChanged;
  final void Function(double?) onMinSalienceChanged;

  const MemoryRetrievePanel({
    super.key,
    required this.state,
    required this.onRetrieve,
    required this.onLimitChanged,
    required this.onMinSalienceChanged,
  });

  @override
  State<MemoryRetrievePanel> createState() => _MemoryRetrievePanelState();
}

class _MemoryRetrievePanelState extends State<MemoryRetrievePanel> {
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _limitController = TextEditingController();
  final TextEditingController _minSalienceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _limitController.text = widget.state.retrieveLimit.toString();
    _minSalienceController.text =
        widget.state.minSalience?.toStringAsFixed(2) ?? '';
  }

  @override
  void didUpdateWidget(covariant MemoryRetrievePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.retrieveLimit != widget.state.retrieveLimit &&
        _limitController.text != widget.state.retrieveLimit.toString()) {
      _limitController.text = widget.state.retrieveLimit.toString();
    }
    final minSalienceText = widget.state.minSalience?.toStringAsFixed(2) ?? '';
    if (oldWidget.state.minSalience != widget.state.minSalience &&
        _minSalienceController.text != minSalienceText) {
      _minSalienceController.text = minSalienceText;
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _limitController.dispose();
    _minSalienceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pack = widget.state.retrievedPack;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Retrieve Context',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _queryController,
          decoration: InputDecoration(
            labelText: 'Query',
            hintText: 'Search the selected memory scope',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => widget.onRetrieve(_queryController.text),
              tooltip: 'Retrieve memory',
            ),
          ),
          onSubmitted: (value) => widget.onRetrieve(value),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _limitController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Limit',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  final parsed = int.tryParse(value.trim());
                  if (parsed != null) {
                    widget.onLimitChanged(parsed);
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _minSalienceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Min salience',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  final trimmed = value.trim();
                  widget.onMinSalienceChanged(
                    trimmed.isEmpty ? null : double.tryParse(trimmed),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => widget.onRetrieve(_queryController.text),
            icon: const Icon(Icons.travel_explore),
            label: const Text('Retrieve memory'),
          ),
        ),
        if (pack != null) ...[
          const SizedBox(height: 16),
          _buildPackSummary(context, pack),
          const SizedBox(height: 12),
          if (pack.items.isEmpty)
            const Text('No memory results were returned.')
          else
            ...pack.items.map((item) => _buildResultCard(context, item)),
        ],
      ],
    );
  }

  Widget _buildPackSummary(BuildContext context, MemoryPack pack) {
    final chips = <Widget>[Chip(label: Text('${pack.items.length} items'))];
    if (pack.requestId != null) {
      chips.add(Chip(label: Text('Request ${pack.requestId}')));
    }
    if (pack.mode != null && pack.mode!.isNotEmpty) {
      chips.add(Chip(label: Text(pack.mode!)));
    }
    if (pack.tokenBudget?.maxTokens != null) {
      chips.add(
        Chip(
          label: Text(
            '${pack.tokenBudget!.usedTokens ?? 0}/${pack.tokenBudget!.maxTokens} tokens',
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Results', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: chips),
        if (pack.tokenBudget != null) ...[
          const SizedBox(height: 8),
          Text(
            'Budget: ${_budgetSummary(pack.tokenBudget!)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (pack.dropped.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Dropped: ${pack.dropped.length}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (pack.conflicts.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Conflicts: ${pack.conflicts.length}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (pack.metadata.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Pack metadata'),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  prettyJson(pack.metadata),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildResultCard(BuildContext context, MemoryRecord item) {
    final metadata = item.metadata;
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
          _buildDetailRow('Type', item.memoryType),
          if (item.salienceHint != null)
            _buildDetailRow(
              'Salience hint',
              item.salienceHint!.toStringAsFixed(2),
            ),
          if (item.retentionHint != null)
            _buildDetailRow(
              'Retention hint',
              item.retentionHint!.toStringAsFixed(2),
            ),
          if (item.salience != null)
            _buildDetailRow('Salience', item.salience!.toStringAsFixed(2)),
          if (item.retentionScore != null)
            _buildDetailRow(
              'Retention score',
              item.retentionScore!.toStringAsFixed(2),
            ),
          if (item.rankScore != null)
            _buildDetailRow('Rank score', item.rankScore!.toStringAsFixed(2)),
          if (item.tokenEstimate != null)
            _buildDetailRow('Tokens', item.tokenEstimate.toString()),
          _buildDetailRow('Pinned', item.pinned ? 'Yes' : 'No'),
          if (item.expiresAt != null)
            _buildDetailRow('Expires', item.expiresAt!.toIso8601String()),
          if (item.createdAt != null)
            _buildDetailRow('Created', item.createdAt!.toIso8601String()),
          if (item.updatedAt != null)
            _buildDetailRow('Updated', item.updatedAt!.toIso8601String()),
          if (item.whySelected != null && item.whySelected!.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Why selected',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(item.whySelected!),
            ),
          ],
          if (metadata.isNotEmpty) ...[
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
              child: SelectableText(prettyJson(metadata)),
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

  String _subtitleFor(MemoryRecord item) {
    final parts = <String>[
      if (item.memoryType.isNotEmpty) item.memoryType,
      if (item.salienceHint != null)
        'salience ${item.salienceHint!.toStringAsFixed(2)}',
      if (item.retentionHint != null)
        'retention ${item.retentionHint!.toStringAsFixed(2)}',
      if (item.pinned) 'pinned',
    ];
    if (parts.isEmpty) {
      return item.contentPreview ?? 'Memory record';
    }
    return parts.join(' | ');
  }

  String _budgetSummary(MemoryPackBudget budget) {
    final parts = <String>[];
    if (budget.usedTokens != null && budget.maxTokens != null) {
      parts.add('${budget.usedTokens}/${budget.maxTokens} used');
    }
    if (budget.shortTermUsed != null) {
      parts.add('short ${budget.shortTermUsed}');
    }
    if (budget.longTermUsed != null) {
      parts.add('long ${budget.longTermUsed}');
    }
    if (budget.persistentUsed != null) {
      parts.add('persistent ${budget.persistentUsed}');
    }
    return parts.isEmpty ? 'No budget data' : parts.join(' | ');
  }
}
