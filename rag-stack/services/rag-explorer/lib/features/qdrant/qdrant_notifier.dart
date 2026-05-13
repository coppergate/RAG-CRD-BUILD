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

  Future<dynamic> _getWithFallback(
    ApiClient client,
    String primaryUrl,
    String fallbackUrl,
  ) async {
    try {
      return (await client.get(primaryUrl)).data;
    } catch (e) {
      _logger.warn('Primary Qdrant request failed for $primaryUrl: $e');
      return (await client.get(fallbackUrl)).data;
    }
  }

  Future<QdrantState> _fetchInitialState() async {
    final config = ref.read(appConfigProvider);
    final client = ApiClient(config);

    try {
      _logger.debug('Loading Qdrant collections');
      final collectionsData = await _getWithFallback(
        client,
        '${config.qdrantDirectUrl}/collections',
        '${config.qdrantUrl}/collections',
      );
      final collections = _extractCollections(collectionsData);

      final details = <Map<String, dynamic>>[];
      for (final coll in collections) {
        final name = (coll['name'] ?? coll['collection_name'] ?? '').toString();
        if (name.isEmpty) {
          continue;
        }
        try {
          final statsJson = await _getWithFallback(
            client,
            '${config.qdrantDirectUrl}/collections/$name/stats',
            '${config.qdrantUrl}/collections/$name/stats',
          );
          final extractedStats = _extractStats(statsJson);
          if (extractedStats == null) {
            _logger.warn(
              'Qdrant stats response for $name had no result payload',
            );
            continue;
          }
          details.add({
            'name': name,
            'stats': QdrantStats.fromJson(extractedStats),
          });
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
    } catch (e) {
      _logger.error('Failed to load Qdrant collections: $e');
      return const QdrantState();
    }
  }

  Future<void> refresh() async {
    _logger.info('Refreshing Qdrant collections');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchInitialState());
  }
}
