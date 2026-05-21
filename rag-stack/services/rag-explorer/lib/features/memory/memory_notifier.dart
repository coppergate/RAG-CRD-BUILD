import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/services/log_service.dart';
import '../../core/services/memory_service.dart';
import 'memory_contracts.dart';

part 'memory_notifier.g.dart';

class MemoryState {
  final MemoryScope scope;
  final List<MemoryRecord> items;
  final MemoryPack? retrievedPack;
  final int retrieveLimit;
  final double? minSalience;
  final bool isLoading;
  final String? error;

  const MemoryState({
    this.scope = const MemoryScope(),
    this.items = const [],
    this.retrievedPack,
    this.retrieveLimit = 10,
    this.minSalience,
    this.isLoading = false,
    this.error,
  });

  MemoryState copyWith({
    MemoryScope? scope,
    List<MemoryRecord>? items,
    MemoryPack? retrievedPack,
    int? retrieveLimit,
    double? minSalience,
    bool? isLoading,
    String? error,
    bool clearRetrievedPack = false,
    bool clearError = false,
  }) {
    return MemoryState(
      scope: scope ?? this.scope,
      items: items ?? this.items,
      retrievedPack: clearRetrievedPack
          ? null
          : retrievedPack ?? this.retrievedPack,
      retrieveLimit: retrieveLimit ?? this.retrieveLimit,
      minSalience: minSalience ?? this.minSalience,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
    );
  }
}

@riverpod
class MemoryNotifier extends _$MemoryNotifier {
  LogNotifier get _logger => ref.read(logProvider.notifier);

  MemoryService get _service => ref.read(memoryServiceProvider);

  @override
  MemoryState build() {
    _logger.debug('Building memory explorer state');
    return const MemoryState();
  }

  String _requestId(String prefix) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
  }

  Future<void> setSession(int? sessionId) async {
    _logger.info('Selecting memory session: ${sessionId ?? "all"}');
    state = state.copyWith(
      scope: state.scope.copyWith(sessionId: sessionId),
      items: const [],
      clearRetrievedPack: true,
      clearError: true,
    );
    if (sessionId != null) {
      await loadItems();
    }
  }

  void setUserId(String userId) {
    state = state.copyWith(
      scope: state.scope.copyWith(
        userId: userId.trim().isEmpty ? null : userId.trim(),
      ),
      clearError: true,
    );
  }

  void setProjectId(String projectId) {
    final parsed = int.tryParse(projectId.trim());
    state = state.copyWith(
      scope: state.scope.copyWith(projectId: parsed),
      clearError: true,
    );
  }

  void setTags(String tagsText) {
    final tags = tagsText
        .split(RegExp(r'[\s,;]+'))
        .map((tag) => int.tryParse(tag.trim()))
        .whereType<int>()
        .toList();
    state = state.copyWith(
      scope: state.scope.copyWith(tags: tags),
      clearError: true,
    );
  }

  void setRetrieveLimit(int limit) {
    state = state.copyWith(
      retrieveLimit: limit.clamp(1, 1000),
      clearError: true,
    );
  }

  void setMinSalience(double? value) {
    state = state.copyWith(minSalience: value, clearError: true);
  }

  Future<void> loadItems() async {
    final sessionId = state.scope.sessionId;
    if (sessionId == null) return;

    _logger.debug('Loading memory items for session $sessionId');
    state = state.copyWith(isLoading: true, clearError: true);
    final items = await _service.getMemoryItems(sessionId);
    state = state.copyWith(items: items, isLoading: false);
  }

  Future<void> writeMemory(MemoryRecord item) async {
    final sessionId = state.scope.sessionId;
    if (sessionId == null) return;

    final request = MemoryWriteRequest(
      requestId: _requestId('mem-write'),
      correlationId: _requestId('mem-corr'),
      scope: state.scope,
      writes: [item],
    );

    _logger.info(
      'Writing memory item for session $sessionId (${item.memoryType})',
    );
    state = state.copyWith(isLoading: true, clearError: true);
    final success = await _service.writeMemory(request);
    if (success) {
      await loadItems();
    } else {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to write memory item',
      );
    }
  }

  Future<void> retrieve(String query) async {
    final sessionId = state.scope.sessionId;
    if (sessionId == null) return;

    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      state = state.copyWith(error: 'Enter a query to retrieve memory context');
      return;
    }

    _logger.info('Retrieving memory for session $sessionId: $normalizedQuery');
    state = state.copyWith(isLoading: true, clearError: true);
    final pack = await _service.retrieveMemory(
      MemoryRetrieveRequest(
        requestId: _requestId('mem-retrieve'),
        correlationId: _requestId('mem-corr'),
        scope: state.scope,
        query: normalizedQuery,
        limit: state.retrieveLimit,
        minSalience: state.minSalience,
      ),
    );
    state = state.copyWith(
      retrievedPack: pack,
      isLoading: false,
      error: pack == null ? 'No memory results were returned' : null,
    );
  }
}
