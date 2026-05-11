import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/models/metrics.dart';
import '../../core/api_client.dart';
import '../../app_config_provider.dart';

part 'qdrant_notifier.freezed.dart';
part 'qdrant_notifier.g.dart';

@freezed
class QdrantState with _$QdrantState {
  const factory QdrantState({
    @Default([]) List<Map<String, dynamic>> collections,
    @Default(false) bool isLoading,
  }) = _QdrantState;
}

@riverpod
class QdrantNotifier extends _$QdrantNotifier {
  @override
  FutureOr<QdrantState> build() async {
    return _fetchInitialState();
  }

  Future<QdrantState> _fetchInitialState() async {
    final config = ref.read(appConfigProvider);
    final client = ApiClient(config);
    
    final response = await client.get('${config.qdrantUrl}/collections');
    final collections = (response.data['result']['collections'] as List);
    
    List<Map<String, dynamic>> details = [];
    for (var coll in collections) {
      final name = coll['name'];
      final statsResp = await client.get('${config.qdrantUrl}/collections/$name/stats');
      details.add({
        'name': name,
        'stats': QdrantStats.fromJson(statsResp.data),
      });
    }
    return QdrantState(collections: details);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchInitialState());
  }
}
