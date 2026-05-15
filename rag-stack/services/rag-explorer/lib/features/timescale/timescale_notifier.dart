import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/models/session.dart';
import '../../core/models/tag.dart';
import '../../core/models/metrics.dart';
import '../../core/api_client.dart';
import '../../app_config_provider.dart';
import '../../core/services/log_service.dart';

part 'timescale_notifier.freezed.dart';
part 'timescale_notifier.g.dart';

@freezed
abstract class TimescaleState with _$TimescaleState {
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
  LogNotifier get _logger => ref.read(logProvider.notifier);

  Session? _parseSession(dynamic item) {
    try {
      if (item is Map<String, dynamic>) {
        return Session.fromJson(item);
      }
      if (item is Map) {
        return Session.fromJson(Map<String, dynamic>.from(item));
      }
    } catch (e) {
      _logger.warn('Skipping malformed Timescale session payload: $e');
    }
    return null;
  }

  Tag? _parseTag(dynamic item) {
    try {
      if (item is Map<String, dynamic>) {
        return Tag.fromJson(item);
      }
      if (item is Map) {
        return Tag.fromJson(Map<String, dynamic>.from(item));
      }
    } catch (e) {
      _logger.warn('Skipping malformed Timescale tag payload: $e');
    }
    return null;
  }

  AuditEntry? _parseAuditEntry(dynamic item) {
    try {
      if (item is Map<String, dynamic>) {
        return AuditEntry.fromJson(item);
      }
      if (item is Map) {
        return AuditEntry.fromJson(Map<String, dynamic>.from(item));
      }
    } catch (e) {
      _logger.warn('Skipping malformed Timescale audit payload: $e');
    }
    return null;
  }

  @override
  FutureOr<TimescaleState> build() async {
    return _fetchInitialState();
  }

  Future<TimescaleState> _fetchInitialState() async {
    final config = ref.read(appConfigProvider);
    final client = ApiClient(config);
    try {
      _logger.debug('Loading Timescale sessions and tags');
      final sessResp = await client.get('${config.dbUrl}/sessions');
      final tagResp = await client.get('${config.dbUrl}/tags');

      final List<dynamic> sessData = sessResp.data ?? [];
      final List<dynamic> tagData = tagResp.data ?? [];

      return TimescaleState(
        sessions: sessData.map(_parseSession).whereType<Session>().toList(),
        availableTags: tagData.map(_parseTag).whereType<Tag>().toList(),
      );
    } catch (e) {
      _logger.error('Failed to load Timescale overview: $e');
      return const TimescaleState();
    }
  }

  Future<void> refresh() async {
    _logger.info('Refreshing Timescale dashboard');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchInitialState());
  }

  Future<void> selectSession(Session session) async {
    final currentState = state.value ?? const TimescaleState();
    _logger.info('Loading Timescale details for session ${session.id}');
    state = AsyncData(
      currentState.copyWith(
        selectedSession: session,
        isLoadingDetails: true,
        currentHealth: null,
        auditLogs: null,
      ),
    );

    try {
      final config = ref.read(appConfigProvider);
      final client = ApiClient(config);

      final healthResp = await client.get(
        '${config.dbUrl}/sessions/${session.id}/health',
      );
      final auditResp = await client.get(
        '${config.dbUrl}/audit/sessions/${session.id}',
      );

      final List<dynamic> auditData = auditResp.data ?? [];

      state = AsyncData(
        state.value!.copyWith(
          currentHealth: healthResp.data != null
              ? SessionHealth.fromJson(healthResp.data)
              : null,
          auditLogs: auditData
              .map(_parseAuditEntry)
              .whereType<AuditEntry>()
              .toList(),
          isLoadingDetails: false,
        ),
      );
      _logger.info(
        'Loaded Timescale details for session ${session.id}: audit_logs=${auditData.length}',
      );
    } catch (e) {
      _logger.error('Failed to load Timescale session ${session.id}: $e');
      state = AsyncData(state.value!.copyWith(isLoadingDetails: false));
    }
  }

  Future<void> mergeTags(List<int> sourceTagIds, int targetTagId) async {
    final config = ref.read(appConfigProvider);
    final client = ApiClient(config);
    _logger.warn(
      'Merging Timescale tags source=${sourceTagIds.join(",")} target=$targetTagId',
    );
    await client.post(
      '${config.dbUrl}/maintenance/tags/merge',
      data: {'source_tag_ids': sourceTagIds, 'target_tag_id': targetTagId},
    );
  }
}
