import 'package:flutter/material.dart';
import '../../core/models/behavioral_rule.dart';

class RulesList extends StatelessWidget {
  final List<BehavioralRule> rules;
  final Function(BehavioralRule) onAccept;
  final Function(BehavioralRule) onDelete;

  const RulesList({
    super.key,
    required this.rules,
    required this.onAccept,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (rules.isEmpty) {
      return const Center(child: Text('No behavioral rules found.'));
    }

    return ListView.builder(
      itemCount: rules.length,
      itemBuilder: (context, index) {
        final rule = rules[index];
        final isPending = rule.state == 'PENDING';

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ExpansionTile(
            title: Row(
              children: [
                _buildStatusChip(rule.state),
                const SizedBox(width: 8),
                Text(rule.actionType, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            subtitle: Text('Updated: ${rule.updatedAt.toString().split(' ')[0]}'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Rule Content:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                        fontFamily: 'monospace',
                      ),
                      child: Text(rule.ruleContent),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isPending)
                          ElevatedButton.icon(
                            icon: const Icon(Icons.check),
                            label: const Text('Accept'),
                            onPressed: () => onAccept(rule),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                          ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
                          onPressed: () => onDelete(rule),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusChip(String state) {
    Color color = Colors.grey;
    if (state == 'ACTIVE') color = Colors.green;
    if (state == 'PENDING') color = Colors.orange;

    return Chip(
      label: Text(state, style: const TextStyle(fontSize: 10, color: Colors.white)),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
