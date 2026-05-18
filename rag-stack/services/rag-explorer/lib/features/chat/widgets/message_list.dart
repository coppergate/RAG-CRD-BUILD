import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
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
      return const Center(child: Text('No messages yet. Send a prompt to start.'));
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

  Widget _buildMessageBubble(BuildContext context, ResponseMessage msg, int index) {
    final isUser = msg.role == 'user';
    final isSelected = selectedMessageIndex == index;
    
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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
                ),
                Text(
                  msg.timestamp.toString().split(' ').last.substring(0, 5),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (msg.planningResponse != null && msg.planningResponse!.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.teal.shade900.withValues(alpha: 0.3) : Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.teal.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('PLANNING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal)),
                    const SizedBox(height: 4),
                    MarkdownBody(
                      data: msg.planningResponse!,
                      styleSheet: _getMarkdownStyle(isDarkMode),
                    ),
                  ],
                ),
              ),
            if (msg.content.isNotEmpty)
              MarkdownBody(
                data: msg.content,
                styleSheet: _getMarkdownStyle(isDarkMode),
              )
            else if (isStreaming && index == messages.length - 1)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
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
