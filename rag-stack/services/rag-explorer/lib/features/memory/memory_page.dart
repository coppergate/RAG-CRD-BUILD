import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../chat/chat_notifier.dart';
import 'memory_notifier.dart';

class MemoryPage extends ConsumerStatefulWidget {
  const MemoryPage({super.key});

  @override
  ConsumerState<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends ConsumerState<MemoryPage> {
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _queryController = TextEditingController();
  String _memoryType = 'short';

  @override
  void dispose() {
    _contentController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          _buildSessionSelector(chatState, memoryState, notifier),
          if (memoryState.sessionId != null)
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildMemoryItemsList(memoryState),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    flex: 1,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildWriteForm(notifier),
                          const Divider(height: 32),
                          _buildRetrievePanel(memoryState, notifier),
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

  Widget _buildSessionSelector(dynamic chatState, MemoryState memoryState, MemoryNotifier notifier) {
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

  Widget _buildMemoryItemsList(MemoryState state) {
    if (state.items.isEmpty) {
      return const Center(child: Text('No memory items found for this session.'));
    }

    return ListView.builder(
      itemCount: state.items.length,
      itemBuilder: (context, index) {
        final item = state.items[index] as Map<String, dynamic>;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: Text(item['content'] ?? ''),
            subtitle: Text('Type: ${item['type']} | Salience: ${item['salience']}'),
            trailing: Text(item['timestamp']?.toString().split('T').last.substring(0, 5) ?? ''),
          ),
        );
      },
    );
  }

  Widget _buildWriteForm(MemoryNotifier notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Write Memory', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextField(
          controller: _contentController,
          decoration: const InputDecoration(
            labelText: 'Memory Content',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _memoryType,
          decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'short', child: Text('Short-term')),
            DropdownMenuItem(value: 'long', child: Text('Long-term')),
            DropdownMenuItem(value: 'core', child: Text('Core')),
          ],
          onChanged: (val) => setState(() => _memoryType = val!),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            if (_contentController.text.isNotEmpty) {
              notifier.writeMemory(_contentController.text, _memoryType);
              _contentController.clear();
            }
          },
          child: const Text('Write to Memory'),
        ),
      ],
    );
  }

  Widget _buildRetrievePanel(MemoryState state, MemoryNotifier notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Retrieve Simulation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Test what the LLM would recall for a query:', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _queryController,
                decoration: const InputDecoration(
                  hintText: 'Search query...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => notifier.retrieve(_queryController.text),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (state.retrievedPack != null) ...[
          Text('Recalled ${state.retrievedPack!.memories.length} items:', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...state.retrievedPack!.memories.map((m) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.1)),
              ),
              child: Text(m.toString(), style: const TextStyle(fontSize: 12)),
            );
          }),
        ],
      ],
    );
  }
}
