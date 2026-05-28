import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_notifier.dart';
import 'memory_notifier.dart';
import 'widgets/memory_list.dart';
import 'widgets/memory_retrieve_panel.dart';
import 'widgets/memory_write_form.dart';

class MemoryPage extends ConsumerStatefulWidget {
  const MemoryPage({super.key});

  @override
  ConsumerState<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends ConsumerState<MemoryPage> {
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _projectIdController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();

  @override
  void dispose() {
    _userIdController.dispose();
    _projectIdController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider).value;
    final memoryState = ref.watch(memoryProvider);
    final notifier = ref.read(memoryProvider.notifier);
    final sessions = chatState?.sessions ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory Explorer'),
        actions: [
          if (memoryState.isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => notifier.loadItems(),
            tooltip: 'Refresh stored memory',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildScopeBand(context, sessions, memoryState, notifier),
          if (memoryState.error != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                memoryState.error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          Expanded(
            child: memoryState.scope.sessionId == null
                ? const Center(
                    child: Text('Select a session to explore memory'),
                  )
                : Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Stored Memory',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: MemoryList(items: memoryState.items),
                              ),
                            ],
                          ),
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
                              MemoryWriteForm(onWrite: notifier.writeMemory),
                              const Divider(height: 32),
                              MemoryRetrievePanel(
                                state: memoryState,
                                onRetrieve: notifier.retrieve,
                                onLimitChanged: notifier.setRetrieveLimit,
                                onMinSalienceChanged: notifier.setMinSalience,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeBand(
    BuildContext context,
    List<dynamic> sessions,
    MemoryState memoryState,
    MemoryNotifier notifier,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 320,
            child: DropdownButtonFormField<int>(
              initialValue: sessions.any((s) => s.id == memoryState.scope.sessionId)
                  ? memoryState.scope.sessionId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Session',
                border: OutlineInputBorder(),
              ),
              hint: const Text('Select a session'),
              items: sessions.map<DropdownMenuItem<int>>((s) {
                return DropdownMenuItem<int>(
                  value: s.id as int,
                  child: Text(_sessionLabel(s)),
                );
              }).toList(),
              onChanged: (val) => notifier.setSession(val),
            ),
          ),
          SizedBox(
            width: 180,
            child: TextField(
              controller: _userIdController,
              decoration: const InputDecoration(
                labelText: 'User ID',
                border: OutlineInputBorder(),
              ),
              onChanged: notifier.setUserId,
            ),
          ),
          SizedBox(
            width: 180,
            child: TextField(
              controller: _projectIdController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Project ID',
                border: OutlineInputBorder(),
              ),
              onChanged: notifier.setProjectId,
            ),
          ),
          SizedBox(
            width: 340,
            child: TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: 'Tags',
                hintText: 'Comma-separated tag IDs',
                border: OutlineInputBorder(),
              ),
              onChanged: notifier.setTags,
            ),
          ),
          Chip(
            label: Text(
              'Limit ${memoryState.retrieveLimit}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Chip(
            label: Text(
              memoryState.minSalience == null
                  ? 'Min salience off'
                  : 'Min salience ${memoryState.minSalience!.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _sessionLabel(dynamic session) {
    final name = session.name as String?;
    final id = session.id;
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return 'Session $id';
  }
}
