import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/behavioral_rule.dart';
import 'behavior_notifier.dart';

class BehavioralRulesPage extends ConsumerStatefulWidget {
  const BehavioralRulesPage({super.key});

  @override
  ConsumerState<BehavioralRulesPage> createState() => _BehavioralRulesPageState();
}

class _BehavioralRulesPageState extends ConsumerState<BehavioralRulesPage> {
  final TextEditingController _ruleController = TextEditingController();
  String? _selectedActionType;

  @override
  void dispose() {
    _ruleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final behaviorAsync = ref.watch(behaviorNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Behavioral Rules'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(behaviorNotifierProvider.notifier).refresh(),
          ),
        ],
      ),
      body: behaviorAsync.when(
        data: (state) => Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildRulesList(state.rules),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 1,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLearnForm(state.identifiers),
                    const Divider(height: 32),
                    _buildTaxonomyTable(state.identifiers),
                  ],
                ),
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildRulesList(List<BehavioralRule> rules) {
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
                    if (isPending)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => ref.read(behaviorNotifierProvider.notifier).rejectRule(rule.id),
                            child: const Text('Reject', style: TextStyle(color: Colors.red)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => ref.read(behaviorNotifierProvider.notifier).acceptRule(rule.id),
                            child: const Text('Accept'),
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
    if (state == 'REJECTED') color = Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        state,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildLearnForm(List<ActionIdentifier> identifiers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Direct Instruction', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _selectedActionType,
          decoration: const InputDecoration(labelText: 'Action Type', border: OutlineInputBorder()),
          items: identifiers.map((id) => DropdownMenuItem(value: id.actionType, child: Text(id.actionType))).toList(),
          onChanged: (val) => setState(() => _selectedActionType = val),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _ruleController,
          decoration: const InputDecoration(
            labelText: 'Instruction (REMEMBER syntax)',
            hintText: 'e.g. REMEMBER to always greet the user',
            border: OutlineInputBorder(),
          ),
          maxLines: 4,
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: (_selectedActionType != null && _ruleController.text.isNotEmpty)
              ? () {
                  ref.read(behaviorNotifierProvider.notifier).learnRule(_ruleController.text, _selectedActionType!);
                  _ruleController.clear();
                }
              : null,
          child: const Text('Teach Instruction'),
        ),
      ],
    );
  }

  Widget _buildTaxonomyTable(List<ActionIdentifier> identifiers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Action Taxonomy', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Table(
          border: TableBorder.all(color: Colors.grey.shade300),
          children: [
            const TableRow(
              decoration: BoxDecoration(color: Colors.grey),
              children: [
                Padding(padding: EdgeInsets.all(8), child: Text('Action', style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(padding: EdgeInsets.all(8), child: Text('Description', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            ...identifiers.map((id) => TableRow(
                  children: [
                    Padding(padding: const EdgeInsets.all(8), child: Text(id.actionType, style: const TextStyle(fontSize: 12))),
                    Padding(padding: const EdgeInsets.all(8), child: Text(id.description, style: const TextStyle(fontSize: 12))),
                  ],
                )),
          ],
        ),
      ],
    );
  }
}
