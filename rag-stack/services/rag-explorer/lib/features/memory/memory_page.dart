import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../chat/chat_notifier.dart';
import 'memory_notifier.dart';
import 'widgets/memory_list.dart';
import 'widgets/memory_write_form.dart';
import 'widgets/memory_retrieve_panel.dart';

class MemoryPage extends ConsumerWidget {
  const MemoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatNotifierProvider).value;
    final memoryState = ref.watch(memoryNotifierProvider);
    final notifier = ref.read(memoryNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory Explorer'),
        actions: [
          if (memoryState.isLoading)
            const Center(child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => notifier.loadItems(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSessionSelector(context, chatState, memoryState, notifier),
          if (memoryState.sessionId != null)
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: MemoryList(items: memoryState.items),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    flex: 1,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MemoryWriteForm(onWrite: (content, type) => notifier.writeMemory(content, type)),
                          const Divider(height: 32),
                          MemoryRetrievePanel(state: memoryState, onRetrieve: (query) => notifier.retrieve(query)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            const Expanded(
              child: Center(child: Text('Please select a session to explore memory')),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionSelector(BuildContext context, dynamic chatState, MemoryState memoryState, MemoryNotifier notifier) {
    if (chatState == null) return const SizedBox();
    final sessions = chatState.sessions;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).cardColor,
      child: Row(
        children: [
          const Text('Session: ', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<int>(
              value: memoryState.sessionId,
              hint: const Text('Select a session'),
              isExpanded: true,
              items: sessions.map<DropdownMenuItem<int>>((s) {
                return DropdownMenuItem<int>(
                  value: s.id,
                  child: Text(s.name ?? 'Session ${s.id}'),
                );
              }).toList(),
              onChanged: (val) => notifier.setSession(val),
            ),
          ),
        ],
      ),
    );
  }
}
