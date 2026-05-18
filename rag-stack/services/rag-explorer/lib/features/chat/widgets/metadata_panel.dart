import 'package:flutter/material.dart';
import '../../../core/models/response_message.dart';

class MetadataPanel extends StatelessWidget {
  final ResponseMessage? message;
  final double width;
  final Function(double) onWidthChanged;
  final VoidCallback onClose;
  final bool isDarkMode;

  const MetadataPanel({
    super.key,
    required this.message,
    required this.width,
    required this.onWidthChanged,
    required this.onClose,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final metadata = message?.metadata ?? {};
    final List<dynamic> contexts = _extractContexts(metadata);
    final dynamic rawTags = metadata['selected_tags'] ?? metadata['tags'];
    final List<dynamic> selectedTags = rawTags is List ? rawTags : const [];

    return SizedBox(
      width: width,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Response Metadata',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (message == null)
            const Text(
              'Select a message to view its metadata and retrieved context.',
              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
            )
          else ...[
            _buildMetadataItem(
              'Role',
              message!.role?.toUpperCase() ?? 'UNKNOWN',
            ),
            _buildMetadataItem(
              'Time',
              message!.timestamp
                      ?.toIso8601String()
                      .split('T')
                      .last
                      .substring(0, 8) ??
                  'UNKNOWN',
            ),
            if (metadata['latency_ms'] != null)
              _buildMetadataItem('Latency', '${metadata['latency_ms']}ms'),
            if (metadata['prompt_tokens'] != null)
              _buildMetadataItem(
                'Prompt Tokens',
                metadata['prompt_tokens'].toString(),
              ),
            if (metadata['completion_tokens'] != null)
              _buildMetadataItem(
                'Completion Tokens',
                metadata['completion_tokens'].toString(),
              ),
            if (metadata['model'] != null)
              _buildMetadataItem('Model', metadata['model'].toString()),

            if (selectedTags.isNotEmpty) ...[
              const Divider(),
              const Text(
                'Selected Tags',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: selectedTags
                    .map(
                      (tag) => Chip(
                        label: Text(tag.toString()),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ],

            const Divider(),
            const Text(
              'Memory Trace',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (metadata['recursion_budget'] != null)
              _buildMetadataItem(
                'Recursion Budget',
                metadata['recursion_budget'].toString(),
              ),
            if (metadata['memories_recalled'] != null)
              Text(
                'Recalled ${metadata['memories_recalled']} items from session memory.',
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),

            const SizedBox(height: 16),
            Text(
              'Retrieved Context (${contexts.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (contexts.isEmpty)
              const Text(
                'No context was retrieved for this message.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              )
            else
              ...contexts.map((c) {
                final text = c.toString();
                return _buildContextSnippet('Source', text, isDarkMode);
              }),
          ],
        ],
      ),
    );
  }

  List<dynamic> _extractContexts(Map<String, dynamic> metadata) {
    final contexts = <dynamic>[];
    final rawContexts = metadata['contexts'];
    if (rawContexts is List) {
      contexts.addAll(rawContexts);
    }

    if (contexts.isEmpty) {
      final rawChunks = metadata['chunks'];
      if (rawChunks is List) {
        for (final chunk in rawChunks) {
          if (chunk is List) {
            contexts.addAll(chunk);
          } else if (chunk != null) {
            contexts.add(chunk);
          }
        }
      }
    }

    return contexts;
  }

  Widget _buildMetadataItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildContextSnippet(String source, String text, bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.black26 : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDarkMode ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            source,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: isDarkMode ? Colors.white70 : Colors.black87,
            ),
            maxLines: 10,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
