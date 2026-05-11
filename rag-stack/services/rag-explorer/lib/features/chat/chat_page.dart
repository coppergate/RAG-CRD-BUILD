import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rag_explorer/app_config_provider.dart';
import 'chat_notifier.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/message_list.dart';
import 'widgets/metadata_panel.dart';
import 'widgets/session_drawer.dart';
import '../../core/models/session.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  @override
  void dispose() {
    _messageController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatAsync = ref.watch(chatNotifierProvider);
    final darkMode = ref.watch(appConfigProvider).darkMode;
    final availableModels = ref.watch(appConfigProvider).availableModels;

    return chatAsync.when(
      data: (state) => Scaffold(
        appBar: AppBar(
          title: const Text('Chat Explorer'),
          actions: [
            IconButton(
              icon: Icon(state.showMetadata ? Icons.info : Icons.info_outline),
              onPressed: () => ref.read(chatNotifierProvider.notifier).toggleMetadata(),
              tooltip: 'Toggle Metadata Panel',
            ),
          ],
        ),
        body: Row(
          children: [
            SessionDrawer(
              sessions: state.sessions,
              currentSessionId: state.currentSessionId,
              selectedIds: state.selectedSessionIds,
              onSelectSession: (session, isMulti) {
                if (isMulti) {
                  ref.read(chatNotifierProvider.notifier).toggleSessionSelection(session.id);
                } else {
                  ref.read(chatNotifierProvider.notifier).selectSession(session.id);
                }
              },
              onDeleteSession: (session) => _confirmDeleteSession(session),
              onDeleteSelected: _deleteSelectedSessions,
              onNewSession: _startNewSession,
              onRefresh: () => ref.read(chatNotifierProvider.notifier).loadSessions(),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  Expanded(
                    child: MessageList(
                      messages: state.messages,
                      isStreaming: state.isStreaming,
                      selectedMessageIndex: state.selectedMessageIndex,
                      onSelectMessage: (index) => ref.read(chatNotifierProvider.notifier).selectMessage(index),
                      scrollController: _chatScrollController,
                      isDarkMode: darkMode,
                    ),
                  ),
                  ChatInputBar(
                    enabled: state.currentSessionId != null && !state.isStreaming,
                    isStreaming: state.isStreaming,
                    controller: _messageController,
                    onSend: _sendMessage,
                    onStop: () => ref.read(chatNotifierProvider.notifier).stopChat(),
                    planner: state.selectedPlanner,
                    executor: state.selectedExecutor,
                    availableModels: availableModels,
                    availableTags: state.availableTags,
                    selectedTags: state.selectedTags,
                    onPlannerChanged: (val) => ref.read(chatNotifierProvider.notifier).setPlanner(val),
                    onExecutorChanged: (val) => ref.read(chatNotifierProvider.notifier).setExecutor(val),
                    onTagAdded: (tag) => ref.read(chatNotifierProvider.notifier).addTag(tag),
                    onTagRemoved: (tag) => ref.read(chatNotifierProvider.notifier).removeTag(tag),
                    memoryMode: state.memoryMode,
                    onMemoryModeChanged: (val) => ref.read(chatNotifierProvider.notifier).setMemoryMode(val),
                  ),
                ],
              ),
            ),
            if (state.showMetadata) ...[
              _buildResizableDivider(state),
              MetadataPanel(
                message: (state.selectedMessageIndex != null && state.selectedMessageIndex! < state.messages.length)
                    ? state.messages[state.selectedMessageIndex!]
                    : null,
                width: state.metadataPanelWidth,
                onWidthChanged: (val) => ref.read(chatNotifierProvider.notifier).setMetadataPanelWidth(val),
                onClose: () => ref.read(chatNotifierProvider.notifier).selectMessage(null),
                isDarkMode: darkMode,
              ),
            ],
          ],
        ),
      ),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, stack) => Scaffold(body: Center(child: Text('Error: $err'))),
    );
  }

  void _sendMessage() {
    final prompt = _messageController.text;
    if (prompt.isEmpty) return;
    _messageController.clear();
    ref.read(chatNotifierProvider.notifier).sendMessage(prompt);
  }

  Widget _buildResizableDivider(ChatState state) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          final newWidth = state.metadataPanelWidth - details.delta.dx;
          ref.read(chatNotifierProvider.notifier).setMetadataPanelWidth(newWidth.clamp(100.0, 800.0));
        },
        child: Container(
          width: 8,
          color: Colors.transparent,
          child: const VerticalDivider(width: 1),
        ),
      ),
    );
  }

  Future<void> _startNewSession() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Session'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: 'Session Name (Optional)'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null) {
      ref.read(chatNotifierProvider.notifier).createSession(name.isEmpty ? 'New Session' : name);
    }
  }

  Future<void> _confirmDeleteSession(Session session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session'),
        content: Text('Are you sure you want to delete "${session.name ?? 'Session ${session.id}'}"?'),
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
      ref.read(chatNotifierProvider.notifier).deleteSession(session.id);
    }
  }

  Future<void> _deleteSelectedSessions() async {
    final state = ref.read(chatNotifierProvider).value;
    if (state == null || state.selectedSessionIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Sessions'),
        content: Text('Are you sure you want to delete ${state.selectedSessionIds.length} sessions?'),
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
      for (final id in state.selectedSessionIds) {
        await ref.read(chatNotifierProvider.notifier).deleteSession(id);
      }
    }
  }
}
