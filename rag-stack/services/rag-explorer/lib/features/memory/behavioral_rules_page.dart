import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'behavior_notifier.dart';
import 'widgets/rules_list.dart';
import 'widgets/learn_form.dart';
import 'widgets/taxonomy_table.dart';

class BehavioralRulesPage extends ConsumerWidget {
  const BehavioralRulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final behaviorAsync = ref.watch(behaviorNotifierProvider);
    final notifier = ref.read(behaviorNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Behavioral Rules'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => notifier.refresh(),
          ),
        ],
      ),
      body: behaviorAsync.when(
        data: (state) => Row(
          children: [
            Expanded(
              flex: 2,
              child: RulesList(
                rules: state.rules,
                onAccept: (rule) => notifier.acceptRule(rule.id),
                onDelete: (rule) => notifier.deleteRule(rule.id),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 1,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LearnForm(
                      actionTypes: state.identifiers,
                      onLearn: (type, content) => notifier.learnRule(type, content),
                    ),
                    const Divider(height: 32),
                    TaxonomyTable(identifiers: state.identifiers),
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
}
