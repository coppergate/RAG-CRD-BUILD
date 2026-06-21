import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/tag.dart';

class ChatInputBar extends StatelessWidget {
  final bool enabled;
  final bool isStreaming;
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final String planner;
  final String executor;
  final String embeddingModel;
  final List<String> availableModels;
  final List<String> availableEmbeddingModels;
  final List<Tag> availableTags;
  final List<Tag> selectedTags;
  final Function(String) onPlannerChanged;
  final Function(String) onExecutorChanged;
  final Function(String) onEmbeddingModelChanged;
  final Function(Tag) onTagAdded;
  final Function(Tag) onTagRemoved;
  final String memoryMode;
  final Function(String) onMemoryModeChanged;

  const ChatInputBar({
    super.key,
    required this.enabled,
    required this.isStreaming,
    required this.controller,
    required this.onSend,
    required this.onStop,
    required this.planner,
    required this.executor,
    required this.embeddingModel,
    required this.availableModels,
    required this.availableEmbeddingModels,
    required this.availableTags,
    required this.selectedTags,
    required this.onPlannerChanged,
    required this.onExecutorChanged,
    required this.onEmbeddingModelChanged,
    required this.onTagAdded,
    required this.onTagRemoved,
    required this.memoryMode,
    required this.onMemoryModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTagsRow(context),
          const SizedBox(height: 8),
          _buildInputRow(context),
          const SizedBox(height: 8),
          _buildConfigRow(context),
        ],
      ),
    );
  }

  Widget _buildConfigRow(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        _buildDropdown('Planner', planner, (val) => onPlannerChanged(val!), items: availableModels),
        _buildDropdown('Executor', executor, (val) => onExecutorChanged(val!), items: availableModels),
        _buildDropdown('Embedding', embeddingModel, (val) => onEmbeddingModelChanged(val!), items: availableEmbeddingModels),
        _buildDropdown('Memory', memoryMode, (val) => onMemoryModeChanged(val!), items: ['off', 'session', 'full']),
      ],
    );
  }

  Widget _buildDropdown(String label, String value, Function(String?) onChanged, {required List<String> items}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            onChanged: onChanged,
            isDense: true,
            items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 12)))).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTagsRow(BuildContext context) {
    return Container(
      height: 40,
      child: Row(
        children: [
          const Icon(Icons.label_outline, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...selectedTags.map((tag) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InputChip(
                    label: Text(tag.name, style: const TextStyle(fontSize: 11)),
                    onDeleted: () => onTagRemoved(tag),
                  ),
                )),
                _buildAddTagAction(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddTagAction(BuildContext context) {
    return PopupMenuButton<Tag>(
      icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.blue),
      tooltip: 'Add Tag',
      onSelected: onTagAdded,
      itemBuilder: (context) => availableTags
          .where((t) => !selectedTags.any((st) => st.id == t.id))
          .map((t) => PopupMenuItem(value: t, child: Text(t.name)))
          .toList(),
    );
  }

  Widget _buildInputRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Focus(
            onKeyEvent: (node, event) {
              if (!enabled || event is! KeyDownEvent) {
                return KeyEventResult.ignored;
              }

              final isEnter =
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.numpadEnter;
              if (!isEnter) {
                return KeyEventResult.ignored;
              }

              if (HardwareKeyboard.instance.isShiftPressed) {
                _insertNewline();
                return KeyEventResult.handled;
              }

              onSend();
              return KeyEventResult.handled;
            },
            child: TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.send,
              minLines: 2,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.all(12),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (isStreaming)
          IconButton(
            icon: const Icon(Icons.stop, color: Colors.red),
            onPressed: onStop,
          )
        else
          IconButton(
            icon: Icon(Icons.send, color: enabled ? Colors.blue : Colors.grey),
            onPressed: enabled ? onSend : null,
          ),
      ],
    );
  }

  void _insertNewline() {
    final value = controller.value;
    final selection = value.selection;
    final text = value.text;

    if (!selection.isValid) {
      controller.value = value.copyWith(
        text: '$text\n',
        selection: TextSelection.collapsed(offset: text.length + 1),
        composing: TextRange.empty,
      );
      return;
    }

    final start = selection.start;
    final end = selection.end;
    final nextText = text.replaceRange(start, end, '\n');
    controller.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }
}
