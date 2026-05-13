import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/models/memory_pack.dart';
import '../../core/models/memory_retrieve_request.dart';
import '../../core/models/memory_write_request.dart';
import '../../core/services/memory_service.dart';
import '../../core/services/log_service.dart';

part 'memory_notifier.freezed.dart';
part 'memory_notifier.g.dart';

@freezed
abstract class MemoryState with _$MemoryState {
  const factory MemoryState({
    int? sessionId,
    @Default([]) List<dynamic> items,
    MemoryPack? retrievedPack,
    @Default(false) bool isLoading,
    String? error,
  }) = _MemoryState;
}

@riverpod
class MemoryNotifier extends _$MemoryNotifier {
  LogNotifier get _logger => ref.read(logProvider.notifier);

  @override
  MemoryState build() {
    _logger.debug('Building memory explorer state');
    return const MemoryState();
  }

  Future<void> setSession(int? sessionId) async {
    _logger.info('Selecting memory session: ${sessionId ?? "all"}');
    state = state.copyWith(
      sessionId: sessionId,
      items: [],
      retrievedPack: null,
    );
    if (sessionId != null) {
      await loadItems();
    }
  }

  Future<void> loadItems() async {
    if (state.sessionId == null) return;
    _logger.debug('Loading memory items for session ${state.sessionId}');
    state = state.copyWith(isLoading: true, error: null);
    final service = ref.read(memoryServiceProvider);
    final items = await service.getMemoryItems(state.sessionId!);
    state = state.copyWith(items: items, isLoading: false);
  }

  Future<void> writeMemory(String content, String type) async {
    if (state.sessionId == null) return;
    _logger.info('Writing memory item for session ${state.sessionId} ($type)');
    state = state.copyWith(isLoading: true, error: null);
    final service = ref.read(memoryServiceProvider);
    final success = await service.writeMemory(
      MemoryWriteRequest(
        content: content,
        type: type,
        sessionId: state.sessionId,
      ),
    );
    if (success) {
      await loadItems();
    } else {
      state = state.copyWith(isLoading: false, error: 'Failed to write memory');
    }
  }

  Future<void> retrieve(String query) async {
    if (state.sessionId == null) return;
    _logger.info('Retrieving memory for session ${state.sessionId}: $query');
    state = state.copyWith(isLoading: true, error: null);
    final service = ref.read(memoryServiceProvider);
    final pack = await service.retrieveMemory(
      MemoryRetrieveRequest(sessionId: state.sessionId!, query: query),
    );
    state = state.copyWith(retrievedPack: pack, isLoading: false);
  }
}
