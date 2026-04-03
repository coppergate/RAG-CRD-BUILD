import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/response_message.dart';
import '../../core/models/session.dart';
import '../../core/services/chat_service.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final List<ResponseMessage> _messages = [];
  List<Session> _sessions = [];
  String _currentSessionId = const Uuid().v4();
  String _selectedPlanner = 'llama3.1';
  String _selectedExecutor = 'llama3.1';
  String _memoryMode = 'off';
  bool _showMetadata = true;
  bool _isStreaming = false;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final chatService = ref.read(chatServiceProvider);
    final sessions = await chatService.getSessions();
    if (mounted) {
      setState(() {
        _sessions = sessions;
      });
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    final chatService = ref.read(chatServiceProvider);
    final success = await chatService.deleteSession(sessionId);
    if (success) {
      if (sessionId == _currentSessionId) {
        _startNewSession();
      }
      _loadSessions();
    }
  }

  void _startNewSession() {
    setState(() {
      _currentSessionId = const Uuid().v4();
      _messages.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Explorer'),
        actions: [
          IconButton(
            icon: Icon(_showMetadata ? Icons.info : Icons.info_outline),
            onPressed: () => setState(() => _showMetadata = !_showMetadata),
            tooltip: 'Toggle Metadata Panel',
          ),
        ],
      ),
      body: Row(
        children: [
          // Left Sub-panel: Session List
          _buildSessionPanel(),
          const VerticalDivider(width: 1),
          // Center: Chat Area
          Expanded(
            flex: 3,
            child: Column(
              children: [
                _buildConfigBar(),
                Expanded(child: _buildMessageList()),
                _buildInputArea(),
              ],
            ),
          ),
          if (_showMetadata) ...[
            const VerticalDivider(width: 1),
            // Right Sub-panel: Metadata
            _buildMetadataPanel(),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionPanel() {
    return SizedBox(
      width: 250,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              onPressed: _startNewSession,
              icon: const Icon(Icons.add),
              label: const Text('New Session'),
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
            ),
          ),
          const Divider(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadSessions,
              child: ListView.builder(
                itemCount: _sessions.length,
                itemBuilder: (context, index) {
                  final session = _sessions[index];
                  final isSelected = session.id == _currentSessionId;
                  return ListTile(
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(session.name ?? 'Session ${session.id.substring(0, 8)}'),
                    subtitle: Text('Last active: ${_formatTime(session.lastActiveAt)}'),
                    selected: isSelected,
                    onTap: () {
                      setState(() {
                        _currentSessionId = session.id;
                        _messages.clear();
                        // In a real app, we would load messages for this session
                      });
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _confirmDeleteSession(session),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  void _confirmDeleteSession(Session session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session?'),
        content: Text('Are you sure you want to delete "${session.name ?? 'this session'}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteSession(session.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).cardColor,
      child: Row(
        children: [
          _buildDropdown('Planner', _selectedPlanner, (val) => setState(() => _selectedPlanner = val!)),
          const SizedBox(width: 16),
          _buildDropdown('Executor', _selectedExecutor, (val) => setState(() => _selectedExecutor = val!)),
          const SizedBox(width: 16),
          _buildDropdown('Memory', _memoryMode, (val) => setState(() => _memoryMode = val!), items: ['off', 'session', 'full']),
          const Spacer(),
          const Text('Tags: ', style: TextStyle(fontSize: 12)),
          const Chip(label: Text('general'), deleteIcon: Icon(Icons.close, size: 12), onDeleted: null),
        ],
      ),
    );
  }

  Widget _buildDropdown(String label, String value, Function(String?) onChanged, {List<String>? items}) {
    final List<String> dropdownItems = items ?? ['llama3.1', 'granite3.1-dense:8b'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            onChanged: onChanged,
            isDense: true,
            items: dropdownItems.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13)))).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return const Center(child: Text('No messages yet. Send a prompt to start.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return _buildMessageBubble(msg);
      },
    );
  }

  Widget _buildMessageBubble(ResponseMessage msg) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? Colors.blue[100] : Colors.grey[200],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isUser ? 12 : 0),
            bottomRight: Radius.circular(isUser ? 0 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUser ? 'User' : 'Assistant',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(msg.content, style: const TextStyle(color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.blue),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataPanel() {
    return SizedBox(
      width: 300,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Response Metadata', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildMetadataItem('Latency', '452ms'),
          _buildMetadataItem('Prompt Tokens', '124'),
          _buildMetadataItem('Completion Tokens', '256'),
          const Divider(),
          const Text('Memory Trace', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Recalled 2 items from session memory.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
          const SizedBox(height: 16),
          const Text('Retrieved Context', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildContextSnippet('doc1.pdf', 'Found similarity 0.89 in collection vectors-384...'),
        ],
      ),
    );
  }

  Widget _buildMetadataItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildContextSnippet(String source, String snippet) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.yellow[50],
        border: Border.all(color: Colors.yellow[200]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(source, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(snippet, style: const TextStyle(fontSize: 10, overflow: TextOverflow.ellipsis), maxLines: 3),
        ],
      ),
    );
  }

  void _sendMessage() {
    if (_messageController.text.isEmpty || _isStreaming) return;

    final userPrompt = _messageController.text;
    setState(() {
      _messages.add(ResponseMessage(
        content: userPrompt,
        role: 'user',
        timestamp: DateTime.now(),
      ));
      _messageController.clear();
      _isStreaming = true;
      
      // Add empty assistant message for streaming
      _messages.add(ResponseMessage(
        content: '',
        role: 'assistant',
        timestamp: DateTime.now(),
      ));
    });

    final chatService = ref.read(chatServiceProvider);
    final stream = chatService.streamChat(
      prompt: userPrompt,
      sessionId: _currentSessionId,
      planner: _selectedPlanner,
      executor: _selectedExecutor,
      tags: ['general'], // Default tag
    );

    stream.listen(
      (chunk) {
        setState(() {
          final lastIndex = _messages.length - 1;
          _messages[lastIndex] = _messages[lastIndex].copyWith(
            content: _messages[lastIndex].content + chunk.content,
            metadata: chunk.metadata,
          );
        });
      },
      onDone: () {
        setState(() {
          _isStreaming = false;
        });
      },
      onError: (err) {
        setState(() {
          _isStreaming = false;
          _messages.add(ResponseMessage(
            content: 'Error: $err',
            role: 'assistant',
            timestamp: DateTime.now(),
          ));
        });
      },
    );
  }
}
