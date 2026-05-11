import 'package:flutter/material.dart';

class MemoryWriteForm extends StatefulWidget {
  final Function(String, String) onWrite;

  const MemoryWriteForm({super.key, required this.onWrite});

  @override
  State<MemoryWriteForm> createState() => _MemoryWriteFormState();
}

class _MemoryWriteFormState extends State<MemoryWriteForm> {
  final TextEditingController _controller = TextEditingController();
  String _type = 'short';

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
        const Text('Write Memory', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          decoration: const InputDecoration(
            hintText: 'Enter memory content...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Type: '),
            DropdownButton<String>(
              value: _type,
              items: const [
                DropdownMenuItem(value: 'short', child: Text('Short-term')),
                DropdownMenuItem(value: 'long', child: Text('Long-term')),
              ],
              onChanged: (val) => setState(() => _type = val!),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () {
                if (_controller.text.isNotEmpty) {
                  widget.onWrite(_controller.text, _type);
                  _controller.clear();
                }
              },
              child: const Text('Write'),
            ),
          ],
        ),
      ],
    );
  }
}
