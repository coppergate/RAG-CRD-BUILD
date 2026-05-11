import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rag_explorer/app_config_provider.dart';
import 'chat_notifier.dart';
import 'chat_dialogs.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/message_list.dart';
import 'widgets/metadata_panel.dart';
import 'widgets/session_drawer.dart';
import 'widgets/resizable_divider.dart';

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

  void _sendMessage() {
    final prompt = _messageController.text;
    if (prompt.isEmpty) return;
    _messageController.clear();
    ref.read(chatNotifierProvider.notifier).sendMessage(prompt);
  }

  @override
  Widget build(BuildContext context) {
    final chatAsync = ref.watch(chatNotifierProvider);
    final config = ref.watch(appConfigProvider);

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
              onSelectSession: (session, isMulti) => isMulti 
                ? ref.read(chatNotifierProvider.notifier).toggleSessionSelection(session.id)
                : ref.read(chatNotifierProvider.notifier).selectSession(session.id),
              onDeleteSession: (s) => ChatDialogs.showDeleteConfirm(context, s).then((val) => val == true ? ref.read(chatNotifierProvider.notifier).deleteSession(s.id) : null),
              onDeleteSelected: () => ChatDialogs.showMultiDeleteConfirm(context, state.selectedSessionIds.length).then((val) => val == true ? _deleteSelected(state.selectedSessionIds) : null),
              onNewSession: () => ChatDialogs.showNewSessionDialog(context).then((val) => val != null ? ref.read(chatNotifierProvider.notifier).createSession(val) : null),
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
                      isDarkMode: config.darkMode,
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
                    availableModels: config.availableModels,
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
              const ResizableDivider(),
              MetadataPanel(
                message: (state.selectedMessageIndex != null && state.selectedMessageIndex! < state.messages.length)
                    ? state.messages[state.selectedMessageIndex!]
                    : null,
                width: state.metadataPanelWidth,
                onWidthChanged: (val) => ref.read(chatNotifierProvider.notifier).setMetadataPanelWidth(val),
                onClose: () => ref.read(chatNotifierProvider.notifier).selectMessage(null),
                isDarkMode: config.darkMode,
              ),
            ],
          ],
        ),
      ),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, stack) => Scaffold(body: Center(child: Text('Error: $err'))),
    );
  }

  void _deleteSelected(Set<int> ids) async {
    for (final id in ids) {
      await ref.read(chatNotifierProvider.notifier).deleteSession(id);
    }
  }
}
