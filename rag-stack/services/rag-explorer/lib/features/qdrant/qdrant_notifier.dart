import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/models/metrics.dart';
import '../../core/api_client.dart';
import '../../app_config_provider.dart';
import '../../core/services/log_service.dart';

part 'qdrant_notifier.freezed.dart';
part 'qdrant_notifier.g.dart';

@freezed
abstract class QdrantState with _$QdrantState {
  const factory QdrantState({
    @Default([]) List<Map<String, dynamic>> collections,
    @Default(false) bool isLoading,
  }) = _QdrantState;
}

@riverpod
class QdrantNotifier extends _$QdrantNotifier {
  LogNotifier get _logger => ref.read(logProvider.notifier);

  @override
  FutureOr<QdrantState> build() async {
    return _fetchInitialState();
  }

  List<Map<String, dynamic>> _extractCollections(dynamic data) {
    if (data is Map<String, dynamic>) {
      final result = data['result'];
      if (result is Map<String, dynamic>) {
        final collections = result['collections'];
        if (collections is List) {
          return collections
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
      if (data['collections'] is List) {
        return (data['collections'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  Map<String, dynamic>? _extractStats(dynamic data) {
    if (data is Map<String, dynamic>) {
      final result = data['result'];
      if (result is Map<String, dynamic>) {
        return result;
      }
      return data;
    }
    return null;
  }

  Future<QdrantState> _fetchInitialState() async {
    final config = ref.read(appConfigProvider);
    final client = ApiClient(config);

    _logger.debug('Loading Qdrant collections');
    final response = await client.get('${config.qdrantUrl}/collections');
    final collections = _extractCollections(response.data);

    final details = <Map<String, dynamic>>[];
    for (final coll in collections) {
      final name = (coll['name'] ?? coll['collection_name'] ?? '').toString();
      if (name.isEmpty) {
        continue;
      }
      try {
        final statsResp = await client.get(
          '${config.qdrantUrl}/collections/$name/stats',
        );
        final statsJson = _extractStats(statsResp.data);
        if (statsJson == null) {
          _logger.warn('Qdrant stats response for $name had no result payload');
          continue;
        }
        details.add({'name': name, 'stats': QdrantStats.fromJson(statsJson)});
      } catch (e) {
        _logger.error('Failed to load Qdrant stats for $name: $e');
        details.add({
          'name': name,
          'stats': QdrantStats(
            status: 'error',
            pointsCount: 0,
            segmentsCount: 0,
            indexedVectorsCount: 0,
            payloadSchema: null,
          ),
        });
      }
    }
    _logger.info('Loaded ${details.length} Qdrant collection(s)');
    return QdrantState(collections: details);
  }

  Future<void> refresh() async {
    _logger.info('Refreshing Qdrant collections');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchInitialState());
  }
}
