import 'dart:convert';

import 'package:flutter/material.dart';

import '../memory_contracts.dart';

class MemoryWriteForm extends StatefulWidget {
  final Future<void> Function(MemoryRecord) onWrite;

  const MemoryWriteForm({super.key, required this.onWrite});

  @override
  State<MemoryWriteForm> createState() => _MemoryWriteFormState();
}

class _MemoryWriteFormState extends State<MemoryWriteForm> {
  final TextEditingController _summaryController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _salienceController = TextEditingController();
  final TextEditingController _retentionController = TextEditingController();
  final TextEditingController _expiresAtController = TextEditingController();
  final TextEditingController _metadataController = TextEditingController();
  final TextEditingController _sourceRefsController = TextEditingController();

  String _memoryType = 'short_term_memory';
  bool _pinned = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _summaryController.dispose();
    _contentController.dispose();
    _salienceController.dispose();
    _retentionController.dispose();
    _expiresAtController.dispose();
    _metadataController.dispose();
    _sourceRefsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Write Memory', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _memoryType,
          decoration: const InputDecoration(
            labelText: 'Memory type',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: 'short_term_memory',
              child: Text('Short-term'),
            ),
            DropdownMenuItem(
              value: 'long_term_memory',
              child: Text('Long-term'),
            ),
            DropdownMenuItem(
              value: 'persistent_memory',
              child: Text('Persistent'),
            ),
          ],
          onChanged: _isSubmitting
              ? null
              : (val) =>
                    setState(() => _memoryType = val ?? 'short_term_memory'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _summaryController,
          decoration: const InputDecoration(
            labelText: 'Summary',
            hintText: 'Short label for the memory item',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _contentController,
          decoration: const InputDecoration(
            labelText: 'Content',
            hintText: 'Memory content',
            border: OutlineInputBorder(),
          ),
          maxLines: 5,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _salienceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Salience hint',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _retentionController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Retention hint',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _expiresAtController,
          decoration: const InputDecoration(
            labelText: 'Expires at',
            hintText: 'ISO-8601 datetime',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _pinned,
          title: const Text('Pinned'),
          onChanged: _isSubmitting
              ? null
              : (val) => setState(() => _pinned = val),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _metadataController,
          decoration: const InputDecoration(
            labelText: 'Metadata JSON',
            hintText: '{"topic":"preferences"}',
            border: OutlineInputBorder(),
          ),
          maxLines: 4,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _sourceRefsController,
          decoration: const InputDecoration(
            labelText: 'Source refs JSON',
            hintText:
                '[{"source_kind":"prompt","source_id":"123","relation_type":"derived"}]',
            border: OutlineInputBorder(),
          ),
          maxLines: 4,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSubmitting ? null : _submit,
            icon: const Icon(Icons.save),
            label: Text(_isSubmitting ? 'Writing...' : 'Write memory'),
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final summary = _summaryController.text.trim();
    final content = _contentController.text.trim();
    if (summary.isEmpty && content.isEmpty) {
      _showError('Add a summary or content before writing memory');
      return;
    }

    final salience = double.tryParse(_salienceController.text.trim());
    final retention = double.tryParse(_retentionController.text.trim());
    final expiresAt = DateTime.tryParse(_expiresAtController.text.trim());

    Map<String, dynamic> metadata = const {};
    final metadataText = _metadataController.text.trim();
    if (metadataText.isNotEmpty) {
      try {
        final decoded = jsonDecode(metadataText);
        if (decoded is Map) {
          metadata = decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        } else {
          _showError('Metadata JSON must decode to an object');
          return;
        }
      } catch (e) {
        _showError('Invalid metadata JSON: $e');
        return;
      }
    }

    List<MemorySourceRef> sourceRefs = const [];
    final sourceRefsText = _sourceRefsController.text.trim();
    if (sourceRefsText.isNotEmpty) {
      try {
        final decoded = jsonDecode(sourceRefsText);
        if (decoded is List) {
          sourceRefs = decoded
              .whereType<Map>()
              .map(
                (entry) => MemorySourceRef.fromJson(
                  entry.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList();
        } else {
          _showError('Source refs JSON must decode to a list');
          return;
        }
      } catch (e) {
        _showError('Invalid source refs JSON: $e');
        return;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      await widget.onWrite(
        MemoryRecord(
          memoryType: _memoryType,
          summary: summary.isEmpty ? null : summary,
          content: content.isEmpty ? null : content,
          salienceHint: salience,
          retentionHint: retention,
          pinned: _pinned,
          expiresAt: expiresAt,
          metadata: metadata,
          sourceRefs: sourceRefs,
        ),
      );
      if (!mounted) return;
      _summaryController.clear();
      _contentController.clear();
      _salienceController.clear();
      _retentionController.clear();
      _expiresAtController.clear();
      _metadataController.clear();
      _sourceRefsController.clear();
      setState(() {
        _memoryType = 'short_term_memory';
        _pinned = false;
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
