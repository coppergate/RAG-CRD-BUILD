import 'package:flutter/material.dart';
import '../memory_notifier.dart';

class MemoryRetrievePanel extends StatefulWidget {
  final MemoryState state;
  final Function(String) onRetrieve;

  const MemoryRetrievePanel({super.key, required this.state, required this.onRetrieve});

  @override
  State<MemoryRetrievePanel> createState() => _MemoryRetrievePanelState();
}

class _MemoryRetrievePanelState extends State<MemoryRetrievePanel> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Retrieve Context', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: 'Search query...',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => widget.onRetrieve(_controller.text),
            ),
          ),
          onSubmitted: widget.onRetrieve,
        ),
        if (widget.state.retrievedPack != null) ...[
          const SizedBox(height: 16),
          const Text('Results:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...widget.state.retrievedPack!.memories.map((m) {
            final memory = m as Map<String, dynamic>;
            return Card(
              color: Colors.blue.shade50,
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(memory['content'] ?? ''),
              ),
            );
          }),
        ],
      ],
    );
  }
}
