import 'package:flutter/material.dart';

class LearnForm extends StatefulWidget {
  final List<String> actionTypes;
  final Function(String, String) onLearn;

  const LearnForm({super.key, required this.actionTypes, required this.onLearn});

  @override
  State<LearnForm> createState() => _LearnFormState();
}

class _LearnFormState extends State<LearnForm> {
  final TextEditingController _controller = TextEditingController();
  String? _selectedAction;

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
        const Text('Learn New Rule', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _selectedAction,
          decoration: const InputDecoration(labelText: 'Action Type', border: OutlineInputBorder()),
          items: widget.actionTypes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (val) => setState(() => _selectedAction = val),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          decoration: const InputDecoration(
            labelText: 'REMEMBER syntax rule...',
            hintText: 'e.g. REMEMBER that users in Germany prefer Metric...',
            border: OutlineInputBorder(),
          ),
          maxLines: 4,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_selectedAction != null && _controller.text.isNotEmpty)
              ? () {
                  widget.onLearn(_selectedAction!, _controller.text);
                  _controller.clear();
                }
              : null,
            child: const Text('Submit to Learner'),
          ),
        ),
      ],
    );
  }
}
