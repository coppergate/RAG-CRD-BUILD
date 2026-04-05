import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rag_explorer/features/settings/settings_page.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/response_message.dart';
import '../../core/models/session.dart';
import '../../core/services/chat_service.dart';
import '../../core/services/log_service.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  List<ResponseMessage> _messages = [];
  List<Session> _sessions = [];
  String? _currentSessionId;
  String? _currentSessionName;
  String _selectedPlanner = 'llama3.1:latest';
  String _selectedExecutor = 'llama3.1:latest';
  String _memoryMode = 'off';
  bool _showMetadata = true;
  bool _showLogs = false;
  bool _isStreaming = false;
  bool _inConversation = false;
  final ScrollController _logScrollController = ScrollController();
  double _metadataPanelWidth = 300.0;
  double _logPanelWidth = 400.0;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _logScrollController.dispose();
    super.dispose();
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
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Chat Session'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            hintText: 'Enter a friendly name for this session',
            labelText: 'Session Name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context);
                final newId = const Uuid().v4();
                final chatService = ref.read(chatServiceProvider);
                
                // Create session in backend
                await chatService.createSession(newId, name);
                
                if (mounted) {
                  setState(() {
                    _currentSessionId = newId;
                    _currentSessionName = name;
                    _messages.clear();
                  });
                  // Refresh the list to show the new session
                  _loadSessions();
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Explorer'),
        actions: [
          IconButton(
            icon: Icon(_showLogs ? Icons.terminal : Icons.terminal_outlined),
            onPressed: () => setState(() => _showLogs = !_showLogs),
            tooltip: 'Toggle Log Panel',
          ),
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
            _buildResizableDivider(
              isLogPanel: false,
              onResizeUpdate: (delta) {
                setState(() {
                  _metadataPanelWidth -= delta;
                  if (_metadataPanelWidth < 100) _metadataPanelWidth = 100;
                  if (_metadataPanelWidth > 800) _metadataPanelWidth = 800;
                });
              },
            ),
            // Right Sub-panel: Metadata
            _buildMetadataPanel(),
          ],
          if (_showLogs) ...[
            _buildResizableDivider(
              isLogPanel: true,
              onResizeUpdate: (delta) {
                setState(() {
                  _logPanelWidth -= delta;
                  if (_logPanelWidth < 100) _logPanelWidth = 100;
                  if (_logPanelWidth > 800) _logPanelWidth = 800;
                });
              },
            ),
            // Right Sub-panel: Logs
            _buildLogPanel(),
          ],
        ],
      ),
    );
  }

  Widget _buildResizableDivider({
    required bool isLogPanel,
    required Function(double delta) onResizeUpdate,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onResizeUpdate(details.delta.dx),
        child: Container(
          width: 8,
          color: Colors.transparent,
          child: const VerticalDivider(width: 1),
        ),
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
                    onTap: () async {
                      final chatService = ref.read(chatServiceProvider);
                      final msgs = await chatService.getMessages(session.id);
                      setState(() {
                        _currentSessionId = session.id;
                        _currentSessionName = session.name;
                        _messages = msgs;
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
    final config = ref.read(appConfigProvider);
    final List<String> dropdownItems = items ?? config.availableModels;
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
            if (msg.content.isEmpty && !isUser && _isStreaming)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(msg.content, style: const TextStyle(color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    final bool isEnabled = _currentSessionId != null && !_isStreaming;
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
              enabled: isEnabled,
              decoration: InputDecoration(
                hintText: _currentSessionId == null ? 'Select or create a session to chat...' : 'Type a message...',
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          IconButton(
            icon: Icon(Icons.send, color: isEnabled ? Colors.blue : Colors.grey),
            onPressed: isEnabled ? _sendMessage : null,
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataPanel() {
    return SizedBox(
      width: _metadataPanelWidth,
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

  Widget _buildLogPanel() {
    final logs = ref.watch(logProvider);
    final darkMode = ref.watch(appConfigProvider).darkMode;
    
    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
      }
    });

    return SizedBox(
      width: _logPanelWidth,
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('System Logs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                    onPressed: () => ref.read(logProvider.notifier).clear(),
                    tooltip: 'Clear Logs',
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: darkMode ? Colors.white.withValues(alpha: .05) : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView.builder(
                  controller: _logScrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    Color color = darkMode ? Colors.white : Colors.black87;
                    if (log.level == 'ERROR') color = darkMode ? Colors.redAccent : Colors.red;
                    if (log.level == 'WARN') color = darkMode ? Colors.yellowAccent : Colors.orange[800]!;
                    if (log.level == 'DEBUG') color = darkMode ? const Color.fromARGB(255, 237, 196, 250) : Colors.blue[800]!;
  
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        log.toString(),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: color,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
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
    if (_messageController.text.isEmpty || _isStreaming || _currentSessionId == null) return;

    final userPrompt = _messageController.text;
    final logger = ref.read(logProvider.notifier);
    
    logger.info('User sending prompt: ${userPrompt.substring(0, userPrompt.length > 20 ? 20 : userPrompt.length)}...');
    
    setState(() {
      _messages.add(ResponseMessage(
        content: userPrompt,
        role: 'user',
        timestamp: DateTime.now(),
      ));
      _messageController.clear();
      _isStreaming = true;
      _inConversation = false; // Reset for new message
      
      // Add empty assistant message for streaming
      _messages.add(ResponseMessage(
        content: '',
        role: 'assistant',
        timestamp: DateTime.now(),
      ));
    });

    final chatService = ref.read(chatServiceProvider);
    logger.debug('Calling chatService.streamChat');
    
    final stream = chatService.streamChat(
      prompt: userPrompt,
      sessionId: _currentSessionId!,
      sessionName: _currentSessionName,
      planner: _selectedPlanner,
      executor: _selectedExecutor,
      tags: ['general'], // Default tag
    );

    stream.listen(
      (chunk) {
        if (chunk.content.isNotEmpty) {
           // We don't want to log every single chunk as it would be too much
           // maybe just the first one?
           if (_messages.last.content.isEmpty) {
             logger.info('Received first chunk from LLM');
           }
        }

        setState(() {
          _inConversation = chunk.inConversation;
          final lastIndex = _messages.length - 1;
          _messages[lastIndex] = _messages[lastIndex].copyWith(
            content: _messages[lastIndex].content + chunk.content,
            metadata: chunk.metadata,
          );
          if (chunk.isLast) {
            _isStreaming = false;
            logger.info('Received last chunk from LLM via isLast flag');
          }
        });
      },
      onDone: () {
        logger.info('Chat stream completed successfully');
        setState(() {
          _isStreaming = false;
        });
        _loadSessions();
      },
      onError: (err) {
        logger.error('Chat stream encountered an error: $err');
        
        // Suppress timeout error if not in conversation
        final isTimeout = err.toString().contains('TimeoutException');
        if (isTimeout && !_inConversation) {
          logger.warn('Suppressing idle timeout error');
          setState(() {
            _isStreaming = false;
            // Remove the empty assistant message if it was never filled
            if (_messages.isNotEmpty && _messages.last.content.isEmpty && _messages.last.role == 'assistant') {
              _messages.removeLast();
            }
          });
          return;
        }

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
