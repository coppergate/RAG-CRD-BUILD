import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/models/metrics.dart';
import '../../core/models/tag.dart';
import '../../core/models/session.dart';
import '../../core/api_client.dart';
import '../../app_config_provider.dart';

part 's3_notifier.freezed.dart';
part 's3_notifier.g.dart';

@freezed
class S3State with _$S3State {
  const factory S3State({
    @Default([]) List<VirtualFile> files,
    @Default([]) List<Tag> availableTags,
    @Default([]) List<Session> availableSessions,
    @Default([]) List<Tag> selectedTags,
    Session? selectedSession,
    @Default({}) Set<String> selectedFilePaths,
    @Default(false) bool isLoading,
    @Default(false) bool isDeleting,
    String? error,
  }) = _S3State;
}

@riverpod
class S3Notifier extends _$S3Notifier {
  @override
  FutureOr<S3State> build() async {
    return _fetchInitialState();
  }

  Future<S3State> _fetchInitialState() async {
    final config = ref.read(appConfigProvider);
    final client = ApiClient(config);
    try {
      final tagsResp = await client.get('${config.dbUrl}/tags');
      final sessResp = await client.get('${config.dbUrl}/sessions');
      
      final List<dynamic> tagsData = tagsResp.data ?? [];
      final List<dynamic> sessData = sessResp.data ?? [];
      
      final state = S3State(
        availableTags: tagsData.map((e) => Tag.fromJson(e)).toList(),
        availableSessions: sessData.map((e) => Session.fromJson(e)).toList(),
      );
      
      return _fetchFiles(state);
    } catch (e) {
      return const S3State();
    }
  }

  Future<S3State> _fetchFiles(S3State currentState) async {
    final config = ref.read(appConfigProvider);
    final client = ApiClient(config);
    
    final queryParams = <String, dynamic>{};
    if (currentState.selectedTags.isNotEmpty) {
      queryParams['tags'] = currentState.selectedTags.map((t) => t.name).toList();
    }
    if (currentState.selectedSession != null) {
      queryParams['session_id'] = currentState.selectedSession!.id;
    }

    final response = await client.get('${config.ragAdminApiUrl}/api/s3/objects', queryParameters: queryParams);
    final List<dynamic> data = response.data ?? [];
    
    return currentState.copyWith(
      files: data.map((e) => VirtualFile.fromJson(e)).toList(),
      isLoading: false,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchInitialState());
  }

  void toggleFileSelection(String path) {
    final currentState = state.value!;
    final newSelection = Set<String>.from(currentState.selectedFilePaths);
    if (newSelection.contains(path)) {
      newSelection.remove(path);
    } else {
      newSelection.add(path);
    }
    state = AsyncData(currentState.copyWith(selectedFilePaths: newSelection));
  }

  void selectAll(List<VirtualFile> files) {
    state = AsyncData(state.value!.copyWith(
      selectedFilePaths: files.map((f) => f.path).toSet(),
    ));
  }

  void clearSelection() {
    state = AsyncData(state.value!.copyWith(selectedFilePaths: {}));
  }

  Future<void> setTags(List<Tag> tags) async {
    state = AsyncData(state.value!.copyWith(selectedTags: tags, isLoading: true));
    state = await AsyncValue.guard(() => _fetchFiles(state.value!));
  }

  Future<void> setSession(Session? session) async {
    state = AsyncData(state.value!.copyWith(selectedSession: session, isLoading: true));
    state = await AsyncValue.guard(() => _fetchFiles(state.value!));
  }

  Future<void> deleteSelected() async {
    final currentState = state.value!;
    state = AsyncData(currentState.copyWith(isDeleting: true));
    
    final config = ref.read(appConfigProvider);
    final client = ApiClient(config);
    
    try {
      for (final path in currentState.selectedFilePaths) {
        final file = currentState.files.firstWhere((f) => f.path == path);
        await client.delete('${config.ragAdminApiUrl}/api/s3/buckets/${file.bucket}/${file.path}');
      }
      await refresh();
    } catch (e) {
      state = AsyncData(state.value!.copyWith(isDeleting: false, error: e.toString()));
    }
  }
}
