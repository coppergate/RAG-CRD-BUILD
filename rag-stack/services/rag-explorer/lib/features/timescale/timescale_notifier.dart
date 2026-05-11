import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/models/session.dart';
import '../../core/models/tag.dart';
import '../../core/models/metrics.dart';
import '../../core/api_client.dart';
import '../../app_config_provider.dart';

part 'timescale_notifier.freezed.dart';
part 'timescale_notifier.g.dart';

@freezed
class TimescaleState with _$TimescaleState {
  const factory TimescaleState({
    @Default([]) List<Session> sessions,
    @Default([]) List<Tag> availableTags,
    Session? selectedSession,
    SessionHealth? currentHealth,
    List<AuditEntry>? auditLogs,
    @Default(false) bool isLoading,
    @Default(false) bool isLoadingDetails,
  }) = _TimescaleState;
}

@riverpod
class TimescaleNotifier extends _$TimescaleNotifier {
  @override
  FutureOr<TimescaleState> build() async {
    return _fetchInitialState();
  }

  Future<TimescaleState> _fetchInitialState() async {
    final config = ref.read(appConfigProvider);
    final client = ApiClient(config);
    try {
      final sessResp = await client.get('${config.dbUrl}/sessions');
      final tagResp = await client.get('${config.dbUrl}/tags');
      
      final List<dynamic> sessData = sessResp.data ?? [];
      final List<dynamic> tagData = tagResp.data ?? [];
      
      return TimescaleState(
        sessions: sessData.map((e) => Session.fromJson(e)).toList(),
        availableTags: tagData.map((e) => Tag.fromJson(e)).toList(),
      );
    } catch (e) {
      return const TimescaleState();
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchInitialState());
  }

  Future<void> selectSession(Session session) async {
    final currentState = state.value ?? const TimescaleState();
    state = AsyncData(currentState.copyWith(
      selectedSession: session,
      isLoadingDetails: true,
      currentHealth: null,
      auditLogs: null,
    ));

    try {
      final config = ref.read(appConfigProvider);
      final client = ApiClient(config);
      
      final healthResp = await client.get('${config.dbUrl}/sessions/${session.id}/health');
      final auditResp = await client.get('${config.dbUrl}/audit/sessions/${session.id}');
      
      final List<dynamic> auditData = auditResp.data ?? [];
      
      state = AsyncData(state.value!.copyWith(
        currentHealth: healthResp.data != null ? SessionHealth.fromJson(healthResp.data) : null,
        auditLogs: auditData.map((e) => AuditEntry.fromJson(e)).toList(),
        isLoadingDetails: false,
      ));
    } catch (e) {
      state = AsyncData(state.value!.copyWith(isLoadingDetails: false));
    }
  }

  Future<void> mergeTags(List<int> sourceTagIds, int targetTagId) async {
    final config = ref.read(appConfigProvider);
    final client = ApiClient(config);
    await client.post('${config.dbUrl}/maintenance/tags/merge', data: {
      'source_tag_ids': sourceTagIds,
      'target_tag_id': targetTagId,
    });
  }
}
