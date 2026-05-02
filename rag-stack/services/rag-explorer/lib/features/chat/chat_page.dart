import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:rag_explorer/app_config_provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/response_message.dart';
import '../../core/models/session.dart';
import '../../core/models/tag.dart';
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
  final Set<String> _selectedSessionIds = {};
  String? _currentSessionId;
  String? _currentSessionName;
  String _selectedPlanner = 'llama3.1:latest';
  String _selectedExecutor = 'llama3.1:latest';
  String _memoryMode = 'off';
  bool _showMetadata = true;
  bool _isStreaming = false;
  bool _inConversation = false;
  final List<Tag> _tags = [];
  List<Tag> _availableTags = [];
  StreamSubscription<ResponseMessage>? _chatSubscription;
  final ScrollController _chatScrollController = ScrollController();
  bool _isChatSelected = false;
  int? _selectedMessageIndex;
  double _metadataPanelWidth = 350.0;

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final chatService = ref.read(chatServiceProvider);
    final tags = await chatService.getTags();
    if (mounted) {
      setState(() {
        _availableTags = tags;
        // If we don't have any tags selected yet and 'general' exists, select it
        if (_tags.isEmpty) {
          try {
            final general = tags.firstWhere((t) => t.name.toLowerCase() == 'general');
            _tags.add(general);
          } catch (_) {
            // No general tag found, that's fine
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    _messageController.dispose();
    _chatScrollController.dispose();
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
        setState(() {
          _currentSessionId = null;
          _currentSessionName = null;
          _messages.clear();
        });
      }
      setState(() {
        _selectedSessionIds.remove(sessionId);
      });
      _loadSessions();
    }
  }

  Future<void> _deleteSelectedSessions() async {
    if (_selectedSessionIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Sessions'),
        content: Text('Are you sure you want to delete ${_selectedSessionIds.length} sessions?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final idsToDelete = _selectedSessionIds.toList();
      for (final id in idsToDelete) {
        await _deleteSession(id);
      }
    }
  }

  void _startNewSession() {
    final nameController = TextEditingController();

    Future<void> handleCreate(BuildContext dialogContext) async {
      final name = nameController.text.trim();
      if (name.isNotEmpty) {
        final newId = const Uuid().v4();
        final chatService = ref.read(chatServiceProvider);

        // Create session in backend
        final session = await chatService.createSession(newId, name);

        if (mounted) {
          if (session != null) {
            setState(() {
              _currentSessionId = newId;
              _currentSessionName = name;
              _messages.clear();
              _tags.clear();
              // Re-apply default tags if needed
              if (_availableTags.isNotEmpty) {
                try {
                  final general = _availableTags.firstWhere((t) => t.name.toLowerCase() == 'general');
                  _tags.add(general);
                } catch (_) {}
              }
            });
          }
          // Close dialog as soon as backend call is done
          Navigator.pop(dialogContext);
          // Refresh list in background (don't await it before popping)
          _loadSessions();
        }
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Chat Session'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            hintText: 'Enter a friendly name for this session',
            labelText: 'Session Name',
          ),
          autofocus: true,
          onSubmitted: (_) => handleCreate(dialogContext),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(
            onPressed: () => handleCreate(dialogContext),
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
                _buildTagsPanel(),
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
                  final isCurrent = session.id == _currentSessionId;
                  final isSelected = _selectedSessionIds.contains(session.id);
                  
                  return ListTile(
                    leading: Icon(isSelected ? Icons.check_box : Icons.chat_bubble_outline, 
                      color: isSelected ? Colors.blue : null),
                    title: Text(session.name ?? 'Session ${session.id.substring(0, 8)}'),
                    subtitle: Text('Last active: ${_formatTime(session.lastActiveAt)}'),
                    selected: isCurrent || isSelected,
                    onTap: () async {
                      final isControlPressed = HardwareKeyboard.instance.isControlPressed || 
                                               HardwareKeyboard.instance.isMetaPressed;
                      
                      if (isControlPressed) {
                        setState(() {
                          if (_selectedSessionIds.contains(session.id)) {
                            _selectedSessionIds.remove(session.id);
                          } else {
                            _selectedSessionIds.add(session.id);
                          }
                        });
                      } else {
                        setState(() {
                          _selectedSessionIds.clear();
                          _selectedSessionIds.add(session.id);
                          _currentSessionId = session.id;
                          _currentSessionName = session.name;
                          _isStreaming = false;
                        });
                        
                        _chatSubscription?.cancel();
                        final chatService = ref.read(chatServiceProvider);
                        final msgs = await chatService.getMessages(session.id);
                        setState(() {
                          _messages = msgs;
                          _tags.clear();
                          if (session.tags != null) {
                            _tags.addAll(session.tags!);
                          }
                        });
                      }
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
          if (_selectedSessionIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton.icon(
                onPressed: _deleteSelectedSessions,
                icon: const Icon(Icons.delete_sweep),
                label: Text('Delete (${_selectedSessionIds.length})'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[50],
                  foregroundColor: Colors.red,
                  minimumSize: const Size.fromHeight(40),
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
    if (_currentSessionId == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text('Select or create a session to start chatting.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(child: Text('No messages yet. Send a prompt to start.'));
    }

    // Auto-scroll chat to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients && !_isChatSelected) {
        _chatScrollController.jumpTo(_chatScrollController.position.maxScrollExtent);
      }
    });

    return SelectionArea(
      onSelectionChanged: (content) {
        final isSelected = content != null && content.plainText.isNotEmpty;
        if (isSelected != _isChatSelected) {
          setState(() {
            _isChatSelected = isSelected;
          });
        }
      },
      child: ListView.builder(
        controller: _chatScrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final msg = _messages[index];
          return _buildMessageBubble(msg, index);
        },
      ),
    );
  }

  MarkdownStyleSheet _getMarkdownStyle(bool isDarkMode) {
    return isDarkMode
        ? MarkdownStyleSheet(
            p: const TextStyle(color: Colors.white70),
            listBullet: const TextStyle(color: Colors.white70),
            h1: const TextStyle(color: Colors.white, fontSize: 24, fontFamily: "Roboto"),
            h2: const TextStyle(color: Colors.white, fontSize: 20, fontFamily: "Roboto"),
            h3: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: "Roboto"),
            h4: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: "Roboto"),
            h5: const TextStyle(color: Colors.white, fontSize: 8, fontFamily: "Roboto"),
            code: TextStyle(
              color: Colors.orangeAccent,
              backgroundColor: Colors.white12,
              fontFamily: 'monospace',
              fontSize: 14,
            ),
            codeblockDecoration: BoxDecoration(
              color: const Color(0xFF1E1E1E), // Darker code block
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white10),
            ),
            codeblockPadding: const EdgeInsets.all(8),
          )
        : MarkdownStyleSheet(
            p: const TextStyle(
              color: Colors.black87,
              backgroundColor: Color.fromARGB(5, 1, 10, 10),
            ),
            listBullet: const TextStyle(color: Colors.black),
            h1: const TextStyle(color: Colors.black, fontSize: 24, fontFamily: "Roboto"),
            h2: const TextStyle(color: Colors.black, fontSize: 20, fontFamily: "Roboto"),
            h3: const TextStyle(color: Colors.black, fontSize: 16, fontFamily: "Roboto"),
            h4: const TextStyle(color: Colors.black, fontSize: 12, fontFamily: "Roboto"),
            h5: const TextStyle(color: Colors.black, fontSize: 8, fontFamily: "Roboto"),
            code: TextStyle(
              color: Colors.redAccent,
              backgroundColor: const Color.fromARGB(5, 10, 20, 20),
              fontFamily: 'monospace',
              fontSize: 14,
            ),
            codeblockDecoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(4),
            ),
            codeblockPadding: const EdgeInsets.all(8),
          );
  }

  Widget _buildMessageBubble(ResponseMessage msg, int index) {
    final isUser = msg.role == 'user';
    final darkMode = ref.watch(appConfigProvider).darkMode;
    final isSelected = _selectedMessageIndex == index;
    
    return GestureDetector(
      onTap: () => setState(() => _selectedMessageIndex = index),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.5),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isUser 
                ? (darkMode ? Colors.blue[900] : Colors.blue[100])
                : (darkMode ? Colors.grey[850] : Colors.grey[200]),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(12),
              topRight: const Radius.circular(12),
              bottomLeft: Radius.circular(isUser ? 12 : 0),
              bottomRight: Radius.circular(isUser ? 0 : 12),
            ),
            border: isSelected ? Border.all(color: Colors.blueAccent, width: 2) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isUser ? 'User' : 'Assistant',
                style: TextStyle(
                  fontSize: 10, 
                  fontWeight: FontWeight.bold, 
                  color: darkMode ? Colors.grey[400] : Colors.grey[600]
                ),
              ),
              const SizedBox(height: 4),
              if (!isUser && msg.planningResponse != null && msg.planningResponse!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: darkMode ? Colors.blueGrey[900] : Colors.blueGrey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: darkMode ? Colors.blueGrey[700]! : Colors.blueGrey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.psychology, size: 14, color: darkMode ? Colors.blueGrey[300] : Colors.blueGrey[600]),
                          const SizedBox(width: 4),
                          Text(
                            'Planner',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: darkMode ? Colors.blueGrey[300] : Colors.blueGrey[600]
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      MarkdownBody(
                        data: msg.planningResponse!,
                        styleSheet: _getMarkdownStyle(darkMode).copyWith(
                          p: TextStyle(fontSize: 11, color: darkMode ? Colors.white60 : Colors.black54),
                        ),
                      ),
                    ],
                  ),
                ),
              if (msg.content.isEmpty && !isUser && _isStreaming && index == _messages.length - 1 && (msg.planningResponse == null || msg.planningResponse!.isEmpty))
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (!isUser)
                MarkdownBody(
                  data: msg.content,
                  selectable: false, // Changed to false as it is now inside SelectionArea
                  styleSheet: _getMarkdownStyle(darkMode),
                )
              else
                Text(
                  msg.content, 
                  style: TextStyle(color: darkMode ? Colors.white70 : Colors.black87)
                ),
            ],
          ),
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
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
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
    final ResponseMessage? selectedMsg = (_selectedMessageIndex != null && _selectedMessageIndex! < _messages.length) 
        ? _messages[_selectedMessageIndex!] 
        : null;
    
    final metadata = selectedMsg?.metadata ?? {};
    final List<dynamic> contexts = (metadata['contexts'] as List<dynamic>?) ?? [];
    final darkMode = ref.watch(appConfigProvider).darkMode;

    return SizedBox(
      width: _metadataPanelWidth,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Response Metadata', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              if (selectedMsg != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _selectedMessageIndex = null),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (selectedMsg == null)
            const Text('Select a message to view its metadata and retrieved context.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
          else ...[
            _buildMetadataItem('Role', selectedMsg.role?.toUpperCase() ?? 'UNKNOWN'),
            _buildMetadataItem('Time', selectedMsg.timestamp?.toIso8601String().split('T').last.substring(0, 8) ?? 'N/A'),
            if (metadata['latency_ms'] != null) _buildMetadataItem('Latency', '${metadata['latency_ms']}ms'),
            if (metadata['prompt_tokens'] != null) _buildMetadataItem('Prompt Tokens', metadata['prompt_tokens'].toString()),
            if (metadata['completion_tokens'] != null) _buildMetadataItem('Completion Tokens', metadata['completion_tokens'].toString()),
            if (metadata['model'] != null) _buildMetadataItem('Model', metadata['model'].toString()),
            
            const Divider(),
            const Text('Memory Trace', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (metadata['recursion_budget'] != null) 
              _buildMetadataItem('Recursion Budget', metadata['recursion_budget'].toString()),
            if (metadata['memories_recalled'] != null)
              Text('Recalled ${metadata['memories_recalled']} items from session memory.', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
            
            const SizedBox(height: 16),
            Text('Retrieved Context (${contexts.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (contexts.isEmpty)
              const Text('No context was retrieved for this message.', style: TextStyle(fontSize: 12, color: Colors.grey))
            else
              ...contexts.map((c) {
                final text = c.toString();
                // Context is usually a string, but it might contain source info if we structured it.
                // For now, let's assume it's a string from the pipeline.
                return _buildContextSnippet('Source', text, darkMode);
              }),
          ],
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

  Widget _buildContextSnippet(String source, String snippet, bool darkMode) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: darkMode ? Colors.blueGrey[900] : Colors.yellow[50],
        border: Border.all(color: darkMode ? Colors.blueGrey[700]! : Colors.yellow[200]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(source, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: darkMode ? Colors.blueAccent : Colors.black87)),
              const Icon(Icons.copy, size: 12, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            snippet, 
            style: TextStyle(fontSize: 11, color: darkMode ? Colors.white70 : Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildTagsPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.5),
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        children: [
          const Icon(Icons.tag, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          const Text('Tags: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ..._tags.map((tag) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Chip(
                      label: Text(tag.name, style: const TextStyle(fontSize: 11)),
                      onDeleted: () async {
                        setState(() => _tags.remove(tag));
                        if (_currentSessionId != null) {
                          final chatService = ref.read(chatServiceProvider);
                          await chatService.updateSessionTags(
                            _currentSessionId!, 
                            _tags.map((t) => t.id).toList()
                          );
                          _loadSessions();
                        }
                      },
                      deleteIcon: const Icon(Icons.close, size: 12),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  )),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    onPressed: _showAddTagDialog,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Add Tag',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddTagDialog() {
    final List<Tag> tempSelected = List.from(_tags);
    final tagController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final displayTags = _availableTags.where((t) => 
            tagController.text.isEmpty || t.name.toLowerCase().contains(tagController.text.toLowerCase())
          ).toList();

          return AlertDialog(
            title: const Text('Associate Tags'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: tagController,
                    decoration: const InputDecoration(
                      hintText: 'Search or add new tag...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: Container(
                      height: 250,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ListView(
                        children: [
                          if (tagController.text.isNotEmpty && !_availableTags.any((t) => t.name.toLowerCase() == tagController.text.trim().toLowerCase()))
                            ListTile(
                              title: Text('Add new: "${tagController.text.trim()}"'),
                              leading: const Icon(Icons.add),
                              onTap: () {
                                final newTagName = tagController.text.trim();
                                if (!tempSelected.any((t) => t.name == newTagName)) {
                                  // Create a temporary tag object for new tags
                                  final newTag = Tag(id: newTagName, name: newTagName);
                                  setDialogState(() => tempSelected.add(newTag));
                                }
                                tagController.clear();
                              },
                            ),
                          ...displayTags.map((tag) => CheckboxListTile(
                            title: Text(tag.name),
                            value: tempSelected.any((t) => t.id == tag.id),
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == true) {
                                  tempSelected.add(tag);
                                } else {
                                  tempSelected.removeWhere((t) => t.id == tag.id);
                                }
                              });
                            },
                          )),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  setState(() {
                    _tags.clear();
                    _tags.addAll(tempSelected);
                  });
                  Navigator.pop(context);
                  
                  // Persist to backend if we have an active session
                  if (_currentSessionId != null) {
                    final chatService = ref.read(chatServiceProvider);
                    await chatService.updateSessionTags(
                      _currentSessionId!, 
                      _tags.map((t) => t.id).toList()
                    );
                    // Reload sessions to refresh the tags in the list model
                    _loadSessions();
                  }
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
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
    
    _chatSubscription?.cancel();
    final stream = chatService.streamChat(
      prompt: userPrompt,
      sessionId: _currentSessionId!,
      sessionName: _currentSessionName,
      planner: _selectedPlanner,
      executor: _selectedExecutor,
      tags: _tags.map((t) => t.id).toList(),
    );

    _chatSubscription = stream.listen(
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
          
          String? currentPlanning = _messages[lastIndex].planningResponse;
          String? newPlanning = chunk.planningResponse;
          String? updatedPlanning = currentPlanning;
          
          if (newPlanning != null) {
            updatedPlanning = (currentPlanning ?? '') + newPlanning;
          }

          _messages[lastIndex] = _messages[lastIndex].copyWith(
            content: _messages[lastIndex].content + chunk.content,
            metadata: chunk.metadata,
            planningResponse: updatedPlanning,
          );
          if (chunk.isLast) {
            _isStreaming = false;
            logger.info('Received last chunk from LLM via isLast flag');
            _chatSubscription?.cancel();
            _loadSessions();
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
        
        final isTimeout = err.toString().contains('TimeoutException');
        
        // Suppress timeout error if we think we are already done or not in conversation
        if (isTimeout && (!_isStreaming || !_inConversation)) {
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
          // Only add error message if it's not a timeout that happened after we started receiving data
          // but we still want to show real errors.
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
