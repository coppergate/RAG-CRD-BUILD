import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/models/response_message.dart';
import '../../core/models/session.dart';
import '../../core/models/tag.dart';
import '../../core/services/chat_service.dart';
import '../../core/services/log_service.dart';

part 'chat_notifier.freezed.dart';
part 'chat_notifier.g.dart';

@freezed
abstract class ChatState with _$ChatState {
  const factory ChatState({
    @Default([]) List<Session> sessions,
    @Default([]) List<Tag> availableTags,
    @Default([]) List<Tag> selectedTags,
    int? currentSessionId,
    String? currentSessionName,
    @Default([]) List<ResponseMessage> messages,
    @Default(false) bool isStreaming,
    @Default(false) bool inConversation,
    int? selectedMessageIndex,
    @Default('llama3.1:latest') String selectedPlanner,
    @Default('llama3.1:latest') String selectedExecutor,
    @Default(true) bool showMetadata,
    @Default(350.0) double metadataPanelWidth,
    @Default({}) Set<int> selectedSessionIds,
    @Default('off') String memoryMode,
  }) = _ChatState;
}

@riverpod
class ChatNotifier extends _$ChatNotifier {
  @override
  FutureOr<ChatState> build() async {
    final chatService = ref.watch(chatServiceProvider);
    final sessions = await chatService.getSessions();
    final availableTags = await chatService.getTags();

    List<Tag> selectedTags = [];
    try {
      final general = availableTags.firstWhere(
        (t) => t.name.toLowerCase() == 'general',
      );
      selectedTags.add(general);
    } catch (_) {}

    return ChatState(
      sessions: sessions,
      availableTags: availableTags,
      selectedTags: selectedTags,
    );
  }

  String _normalizeChatText(String text) {
    return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  Future<void> loadSessions() async {
    final chatService = ref.read(chatServiceProvider);
    ref.read(logProvider.notifier).debug('Refreshing chat session list');
    final sessions = await chatService.getSessions();
    state = AsyncData(state.value!.copyWith(sessions: sessions));
  }

  Future<void> loadTags() async {
    final chatService = ref.read(chatServiceProvider);
    ref.read(logProvider.notifier).debug('Refreshing chat tag list');
    final tags = await chatService.getTags();
    state = AsyncData(state.value!.copyWith(availableTags: tags));
  }

  Future<void> deleteSession(int sessionId) async {
    final chatService = ref.read(chatServiceProvider);
    final success = await chatService.deleteSession(sessionId);
    if (success) {
      final currentState = state.value!;
      var newState = currentState.copyWith(
        selectedSessionIds: currentState.selectedSessionIds
            .where((id) => id != sessionId)
            .toSet(),
      );
      if (sessionId == currentState.currentSessionId) {
        newState = newState.copyWith(
          currentSessionId: null,
          currentSessionName: null,
          messages: [],
        );
      }
      state = AsyncData(newState);
      await loadSessions();
    }
  }

  Future<void> selectSession(int sessionId) async {
    final currentState = state.value!;
    if (currentState.currentSessionId == sessionId) return;

    ref.read(logProvider.notifier).info('Selecting chat session: $sessionId');
    final session = currentState.sessions.firstWhere((s) => s.id == sessionId);
    state = AsyncData(
      currentState.copyWith(
        currentSessionId: sessionId,
        currentSessionName: session.name,
        selectedMessageIndex: null,
      ),
    );

    await loadMessages(sessionId);
  }

  Future<void> loadMessages(int sessionId) async {
    final chatService = ref.read(chatServiceProvider);
    final messages = await chatService.getMessages(sessionId);
    state = AsyncData(state.value!.copyWith(messages: messages));
  }

  void toggleSessionSelection(int sessionId) {
    final currentState = state.value!;
    final newSelection = Set<int>.from(currentState.selectedSessionIds);
    if (newSelection.contains(sessionId)) {
      newSelection.remove(sessionId);
    } else {
      newSelection.add(sessionId);
    }
    state = AsyncData(currentState.copyWith(selectedSessionIds: newSelection));
  }

  void clearSessionSelection() {
    state = AsyncData(state.value!.copyWith(selectedSessionIds: {}));
  }

  void setPlanner(String planner) {
    state = AsyncData(state.value!.copyWith(selectedPlanner: planner));
  }

  void setExecutor(String executor) {
    state = AsyncData(state.value!.copyWith(selectedExecutor: executor));
  }

  void setMemoryMode(String mode) {
    state = AsyncData(state.value!.copyWith(memoryMode: mode));
  }

  void toggleMetadata() {
    state = AsyncData(
      state.value!.copyWith(showMetadata: !state.value!.showMetadata),
    );
  }

  void setMetadataPanelWidth(double width) {
    state = AsyncData(state.value!.copyWith(metadataPanelWidth: width));
  }

  void selectMessage(int? index) {
    state = AsyncData(state.value!.copyWith(selectedMessageIndex: index));
  }

  void addTag(Tag tag) {
    final currentState = state.value!;
    if (!currentState.selectedTags.any((t) => t.id == tag.id)) {
      ref
          .read(logProvider.notifier)
          .info('Added chat tag: ${tag.name} (${tag.id})');
      state = AsyncData(
        currentState.copyWith(
          selectedTags: [...currentState.selectedTags, tag],
        ),
      );
    }
  }

  Map<String, dynamic> _mergeMetadata(
    Map<String, dynamic>? base,
    Map<String, dynamic>? update,
  ) {
    final merged = <String, dynamic>{};
    if (base != null) {
      merged.addAll(base);
    }
    if (update != null) {
      merged.addAll(update);
    }
    return merged;
  }

  List<Map<String, dynamic>> _extractMessageSegments(
    Map<String, dynamic>? metadata,
  ) {
    final rawSegments = metadata?['message_segments'];
    if (rawSegments is! List) {
      return [];
    }

    return rawSegments
        .whereType<Map>()
        .map((segment) => Map<String, dynamic>.from(segment))
        .toList();
  }

  Map<String, dynamic> _appendMessageSegments(
    Map<String, dynamic>? base,
    List<Map<String, dynamic>> segmentsToAppend,
  ) {
    if (segmentsToAppend.isEmpty) {
      return _mergeMetadata(base, null);
    }

    final merged = _mergeMetadata(base, null);
    final segments = _extractMessageSegments(base);
    segments.addAll(segmentsToAppend);
    merged['message_segments'] = segments;
    return merged;
  }

  Map<String, dynamic> _buildMessageSegment({
    required String kind,
    required String content,
  }) {
    return {'kind': kind, 'content': content};
  }

  void removeTag(Tag tag) {
    final currentState = state.value!;
    ref
        .read(logProvider.notifier)
        .info('Removed chat tag: ${tag.name} (${tag.id})');
    state = AsyncData(
      currentState.copyWith(
        selectedTags: currentState.selectedTags
            .where((t) => t.id != tag.id)
            .toList(),
      ),
    );
  }

  Future<void> createSession(String name) async {
    final chatService = ref.read(chatServiceProvider);
    ref.read(logProvider.notifier).info('Creating chat session from UI: $name');
    final session = await chatService.createSession(name);
    if (session != null) {
      await loadSessions();
      await selectSession(session.id);
    }
  }

  void stopChat() {
    // We can't easily cancel the stream from here if it's yield* or await for
    // unless we use a StreamController or similar.
    // But we can update the state to stop streaming.
    if (state.value != null) {
      ref.read(logProvider.notifier).warn('Chat streaming stopped by user');
      state = AsyncData(state.value!.copyWith(isStreaming: false));
    }
  }

  Future<void> sendMessage(String prompt) async {
    final currentState = state.value!;
    if (currentState.currentSessionId == null) return;
    ref
        .read(logProvider.notifier)
        .info(
          'Submitting prompt for session ${currentState.currentSessionId} with tags: ${currentState.selectedTags.map((t) => t.id).join(", ")}',
        );

    // Add user message
    final userMessage = ResponseMessage(
      content: prompt,
      role: 'user',
      timestamp: DateTime.now(),
    );

    // Add empty assistant message
    final assistantMessage = ResponseMessage(
      content: '',
      role: 'assistant',
      timestamp: DateTime.now(),
      metadata: {
        'selected_tags': currentState.selectedTags.map((t) => t.name).toList(),
        'selected_tag_ids': currentState.selectedTags.map((t) => t.id).toList(),
        'session_tags': currentState.selectedTags.map((t) => t.name).toList(),
        'source': 'chat-ui',
        'message_segments': <Map<String, dynamic>>[],
      },
    );

    state = AsyncData(
      currentState.copyWith(
        messages: [...currentState.messages, userMessage, assistantMessage],
        isStreaming: true,
        inConversation: false,
      ),
    );

    final chatService = ref.read(chatServiceProvider);
    final stream = chatService.streamChat(
      prompt: prompt,
      sessionId: currentState.currentSessionId!,
      sessionName: currentState.currentSessionName,
      planner: currentState.selectedPlanner,
      executor: currentState.selectedExecutor,
      tags: currentState.selectedTags.map((t) => t.id).toList(),
    );

    try {
      await for (final chunk in stream) {
        if (!state.value!.isStreaming) break; // User stopped

        final latestState = state.value!;
        final messages = List<ResponseMessage>.from(latestState.messages);
        if (messages.isEmpty) break;

        final lastIndex = messages.length - 1;
        final lastMsg = messages[lastIndex];

        String? updatedPlanning = lastMsg.planningResponse;
        if (chunk.planningResponse != null &&
            chunk.planningResponse!.isNotEmpty) {
          final normalizedChunkPlanning = _normalizeChatText(
            chunk.planningResponse!,
          );
          updatedPlanning =
              _normalizeChatText(updatedPlanning ?? '') + normalizedChunkPlanning;
        }

        final Map<String, dynamic>? updatedMetadata =
            (chunk.metadata != null && chunk.metadata!.isNotEmpty)
            ? _mergeMetadata(lastMsg.metadata, chunk.metadata)
            : lastMsg.metadata;

        final appendedSegments = <Map<String, dynamic>>[];
        if (chunk.planningResponse != null &&
            chunk.planningResponse!.isNotEmpty) {
          appendedSegments.add(
            _buildMessageSegment(
              kind: 'planning',
              content: _normalizeChatText(chunk.planningResponse!),
            ),
          );
        }
        if (chunk.content.isNotEmpty) {
          appendedSegments.add(
            _buildMessageSegment(
              kind: 'content',
              content: _normalizeChatText(chunk.content),
            ),
          );
        }

        messages[lastIndex] = lastMsg.copyWith(
          content:
              _normalizeChatText(lastMsg.content) +
              _normalizeChatText(chunk.content),
          metadata: _appendMessageSegments(updatedMetadata, appendedSegments),
          planningResponse: updatedPlanning,
        );

        state = AsyncData(
          latestState.copyWith(
            messages: messages,
            inConversation: chunk.inConversation,
            isStreaming: !chunk.isLast,
          ),
        );

        if (chunk.isLast) {
          await loadSessions();
          break;
        }
      }
    } catch (e) {
      final latestState = state.value!;
      final messages = List<ResponseMessage>.from(latestState.messages);
      messages.add(
        ResponseMessage(
          content: 'Error: $e',
          role: 'assistant',
          timestamp: DateTime.now(),
          metadata: {'error': true},
        ),
      );
      state = AsyncData(
        latestState.copyWith(messages: messages, isStreaming: false),
      );
    } finally {
      if (state.value!.isStreaming) {
        state = AsyncData(state.value!.copyWith(isStreaming: false));
      }
    }
  }
}
