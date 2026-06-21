import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/response_message.dart';

class MessageList extends StatelessWidget {
  final List<ResponseMessage> messages;
  final bool isStreaming;
  final int? selectedMessageIndex;
  final Function(int?) onSelectMessage;
  final ScrollController scrollController;
  final bool isDarkMode;

  const MessageList({
    super.key,
    required this.messages,
    required this.isStreaming,
    this.selectedMessageIndex,
    required this.onSelectMessage,
    required this.scrollController,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const Center(
        child: Text('No messages yet. Send a prompt to start.'),
      );
    }

    return SelectionArea(
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final msg = messages[index];
          return _buildMessageBubble(context, msg, index);
        },
      ),
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    ResponseMessage msg,
    int index,
  ) {
    final isUser = msg.role == 'user';
    final isSelected = selectedMessageIndex == index;
    final structuredSegments = _messageSegments(msg);
    final hasStructuredSegments = _hasStructuredSegments(msg);

    return GestureDetector(
      onTap: () => onSelectMessage(isSelected ? null : index),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser
              ? (isDarkMode ? Colors.blue.shade900 : Colors.blue.shade50)
              : (isDarkMode ? Colors.grey.shade900 : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: Colors.blue, width: 2) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isUser ? 'User' : 'Assistant',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                Text(
                  msg.timestamp.toString().split(' ').last.substring(0, 5),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (hasStructuredSegments)
              ...structuredSegments.map(
                (segment) => _buildSegment(segment, isDarkMode),
              )
            else ...[
              if (msg.planningResponse != null &&
                  msg.planningResponse!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? Colors.teal.shade900.withValues(alpha: 0.3)
                        : Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.teal.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PLANNING',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      MarkdownBody(
                        data: _normalizeDisplayText(msg.planningResponse!),
                        styleSheet: _getMarkdownStyle(isDarkMode),
                      ),
                    ],
                  ),
                ),
              if (msg.content.isNotEmpty)
                MarkdownBody(
                  data: _normalizeDisplayText(msg.content),
                  styleSheet: _getMarkdownStyle(isDarkMode),
                ),
            ],
            if ((msg.content.isEmpty ||
                    !structuredSegments.any((segment) {
                      return (segment['kind'] ?? '').toString() == 'content';
                    })) &&
                isStreaming &&
                index == messages.length - 1)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (!isUser)
              _buildEmbeddingAdvisory(context, msg),
          ],
        ),
      ),
    );
  }

  Widget _buildEmbeddingAdvisory(BuildContext context, ResponseMessage msg) {
    final raw = msg.metadata?['missing_embeddings'];
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();

    final missing = raw.whereType<Map>().toList();
    if (missing.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber.shade600, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: missing.map<Widget>((entry) {
          final tag = (entry['tag'] ?? '').toString();
          final status = (entry['status'] ?? '').toString();
          final model = (entry['model'] ?? '').toString();
          final tagId = entry['tag_id'];
          final isPendingOrBuilding = status == 'pending' || status == 'building';

          final message = isPendingOrBuilding
              ? '⚠ "$tag" has no $model embeddings yet. '
                'Ingestion has been triggered — results will improve once complete.'
              : '⚠ "$tag" embeddings are stale (new files added since last run). '
                'Results may be missing recent content.';

          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => context.go(
                    '/ingestion',
                    extra: {
                      'model': model,
                      'tag_id': tagId,
                      'tag_name': tag,
                    },
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Go to Ingestion →',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Map<String, dynamic>> _messageSegments(ResponseMessage msg) {
    final metadata = msg.metadata;
    final rawSegments = metadata?['message_segments'];
    if (rawSegments is List && rawSegments.isNotEmpty) {
      return rawSegments
          .whereType<Map>()
          .map((segment) => Map<String, dynamic>.from(segment))
          .toList();
    }

    final fallback = <Map<String, dynamic>>[];
    if (msg.planningResponse != null && msg.planningResponse!.isNotEmpty) {
      fallback.add({'kind': 'planning', 'content': msg.planningResponse!});
    }
    if (msg.content.isNotEmpty) {
      fallback.add({'kind': 'content', 'content': msg.content});
    }
    return fallback;
  }

  bool _hasStructuredSegments(ResponseMessage msg) {
    final rawSegments = msg.metadata?['message_segments'];
    return rawSegments is List && rawSegments.isNotEmpty;
  }

  Widget _buildSegment(Map<String, dynamic> segment, bool isDarkMode) {
    final kind = (segment['kind'] ?? 'content').toString();
    final content = (segment['content'] ?? '').toString();

    if (kind == 'planning') {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDarkMode
              ? Colors.teal.shade900.withValues(alpha: 0.3)
              : Colors.teal.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.teal.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PLANNING',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 4),
            MarkdownBody(
              data: _normalizeDisplayText(content),
              styleSheet: _getMarkdownStyle(isDarkMode),
            ),
          ],
        ),
      );
    }

    if (content.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MarkdownBody(
        data: _normalizeDisplayText(content),
        styleSheet: _getMarkdownStyle(isDarkMode),
      ),
    );
  }

  String _normalizeDisplayText(String text) {
    return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  MarkdownStyleSheet _getMarkdownStyle(bool isDarkMode) {
    return isDarkMode
        ? MarkdownStyleSheet(
            p: const TextStyle(color: Colors.white70),
            listBullet: const TextStyle(color: Colors.white70),
            h1: const TextStyle(color: Colors.white, fontSize: 24),
            h2: const TextStyle(color: Colors.white, fontSize: 20),
            h3: const TextStyle(color: Colors.white, fontSize: 16),
            code: const TextStyle(
              color: Colors.orangeAccent,
              backgroundColor: Colors.white12,
              fontFamily: 'monospace',
              fontSize: 14,
            ),
            codeblockDecoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white10),
            ),
            codeblockPadding: const EdgeInsets.all(8),
          )
        : MarkdownStyleSheet(
            p: const TextStyle(color: Colors.black87),
            listBullet: const TextStyle(color: Colors.black),
            h1: const TextStyle(color: Colors.black, fontSize: 24),
            h2: const TextStyle(color: Colors.black, fontSize: 20),
            h3: const TextStyle(color: Colors.black, fontSize: 16),
            code: const TextStyle(
              color: Colors.redAccent,
              backgroundColor: Color.fromARGB(5, 10, 20, 20),
              fontFamily: 'monospace',
              fontSize: 14,
            ),
            codeblockDecoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            codeblockPadding: const EdgeInsets.all(8),
          );
  }
}
