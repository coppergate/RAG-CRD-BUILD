import 'package:freezed_annotation/freezed_annotation.dart';
import 'dart:convert';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/models/metrics.dart';
import '../../core/models/tag.dart';
import '../../core/models/session.dart';
import '../../core/api_client.dart';
import '../../app_config_provider.dart';
import '../../core/services/log_service.dart';

part 's3_notifier.freezed.dart';
part 's3_notifier.g.dart';

@freezed
abstract class S3State with _$S3State {
  const factory S3State({
    @Default([]) List<String> availableBuckets,
    String? selectedBucket,
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
  LogNotifier get _logger => ref.read(logProvider.notifier);

  @override
  FutureOr<S3State> build() async {
    return _fetchInitialState();
  }

  List<String> _extractBucketNames(dynamic data) {
    if (data is List) {
      return data
          .map((e) {
            if (e is Map<String, dynamic>) {
              final name = e['Name'] ?? e['name'];
              return name == null ? '' : name.toString();
            }
            return e?.toString() ?? '';
          })
          .where((name) => name.isNotEmpty)
          .toList();
    }
    return const [];
  }

  Map<String, dynamic> _asObjectMap(dynamic item) {
    if (item is Map<String, dynamic>) {
      return item;
    }
    if (item is Map) {
      return Map<String, dynamic>.from(item);
    }
    return const {};
  }

  VirtualFile? _parseVirtualFile(dynamic item, String fallbackBucket) {
    final data = _asObjectMap(item);
    if (data.isEmpty) {
      return null;
    }

    final path = (data['Key'] ?? data['key'] ?? data['path'] ?? '').toString();
    if (path.isEmpty) {
      return null;
    }

    final bucket = (data['Bucket'] ?? data['bucket'] ?? fallbackBucket)
        .toString();
    final tagsRaw = data['tags'];
    final tags = tagsRaw is List
        ? tagsRaw.map((e) => e.toString()).toList()
        : <String>[];
    final status = (data['status'] ?? data['StorageClass'] ?? 'AVAILABLE')
        .toString();
    final createdAtRaw =
        data['LastModified'] ?? data['last_modified'] ?? data['created_at'];
    DateTime createdAt = DateTime.now().toUtc();
    if (createdAtRaw is String) {
      createdAt = DateTime.tryParse(createdAtRaw)?.toUtc() ?? createdAt;
    } else if (createdAtRaw is DateTime) {
      createdAt = createdAtRaw.toUtc();
    } else if (createdAtRaw is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(
        createdAtRaw,
        isUtc: true,
      );
    }

    return VirtualFile(
      path: path,
      bucket: bucket.isEmpty ? fallbackBucket : bucket,
      createdAt: createdAt,
      tags: tags,
      status: status.isEmpty ? 'AVAILABLE' : status,
    );
  }

  Tag? _parseTag(dynamic item) {
    final data = _asObjectMap(item);
    if (data.isEmpty) {
      return null;
    }
    try {
      final idRaw = data['id'];
      final nameRaw = data['name'];
      if (idRaw == null || nameRaw == null) {
        _logger.warn('Skipping malformed S3 tag payload: $data');
        return null;
      }
      return Tag.fromJson(data);
    } catch (e) {
      _logger.warn('Skipping malformed S3 tag payload: $e');
      return null;
    }
  }

  Session? _parseSession(dynamic item) {
    final data = _asObjectMap(item);
    if (data.isEmpty) {
      return null;
    }
    try {
      return Session.fromJson(data);
    } catch (e) {
      _logger.warn('Skipping malformed S3 session payload: $e');
      return null;
    }
  }

  String? _chooseBucket(List<String> buckets, String preferred) {
    if (buckets.isEmpty) {
      return null;
    }
    if (buckets.contains(preferred)) {
      return preferred;
    }
    return buckets.first;
  }

  Future<S3State> _fetchInitialState() async {
    final config = ref.read(appConfigProvider);
    final client = ApiClient(config);
    try {
      _logger.debug('Loading S3 browser buckets');
      final bucketsResp = await client.get(
        '${config.ragAdminApiUrl}/api/s3/buckets',
      );
      final buckets = _extractBucketNames(bucketsResp.data);
      final tagsResp = await client.get('${config.dbUrl}/tags');
      final sessResp = await client.get('${config.dbUrl}/sessions');

      final List<dynamic> tagsData = tagsResp.data ?? [];
      final List<dynamic> sessData = sessResp.data ?? [];

      final selectedBucket = _chooseBucket(buckets, config.defaultBucketName);
      final state = S3State(
        availableBuckets: buckets,
        selectedBucket: selectedBucket,
        availableTags: tagsData.map(_parseTag).whereType<Tag>().toList(),
        availableSessions: sessData
            .map(_parseSession)
            .whereType<Session>()
            .toList(),
      );

      if (selectedBucket == null) {
        _logger.warn('No S3 buckets are available for browsing');
        return state;
      }

      return _fetchFiles(state);
    } catch (e) {
      _logger.error('Failed to load S3 browser state: $e');
      return S3State(error: e.toString());
    }
  }

  Future<S3State> _fetchFiles(S3State currentState) async {
    final config = ref.read(appConfigProvider);
    final client = ApiClient(config);

    if (currentState.selectedBucket == null ||
        currentState.selectedBucket!.isEmpty) {
      return currentState.copyWith(
        files: const [],
        isLoading: false,
        error: 'No bucket selected',
      );
    }

    final queryParams = <String, dynamic>{};
    if (currentState.selectedTags.isNotEmpty) {
      queryParams['tags'] = currentState.selectedTags
          .map((t) => t.name)
          .toList();
    }
    if (currentState.selectedSession != null) {
      queryParams['session_id'] = currentState.selectedSession!.id;
    }

    _logger.debug(
      'Loading S3 objects from bucket ${currentState.selectedBucket} with tags=${currentState.selectedTags.map((t) => t.name).toList()} session=${currentState.selectedSession?.id ?? "all"}',
    );
    final response = await client.get(
      '${config.ragAdminApiUrl}/api/s3/buckets/${currentState.selectedBucket}',
      queryParameters: queryParams,
    );
    final dynamic rawData = response.data;
    final List<dynamic> data = rawData is List
        ? rawData
        : rawData is String
        ? jsonDecode(rawData) as List<dynamic>
        : rawData is Map<String, dynamic>
        ? (rawData['objects'] as List<dynamic>? ??
              rawData['items'] as List<dynamic>? ??
              rawData['files'] as List<dynamic>? ??
              const [])
        : const [];

    final files = <VirtualFile>[];
    for (final item in data) {
      final file = _parseVirtualFile(item, currentState.selectedBucket!);
      if (file != null) {
        files.add(file);
      }
    }

    _logger.info(
      'Loaded ${files.length} S3 object(s) from bucket ${currentState.selectedBucket}',
    );

    return currentState.copyWith(files: files, isLoading: false, error: null);
  }

  Future<void> refresh() async {
    _logger.info('Refreshing S3 browser');
    final currentState = state.hasValue ? state.value! : const S3State();
    state = AsyncData(currentState.copyWith(isLoading: true, error: null));
    try {
      final next = await _fetchInitialState();
      state = AsyncData(next);
    } catch (e) {
      _logger.error('Unexpected S3 refresh failure: $e');
      state = AsyncData(
        (state.hasValue ? state.value! : const S3State()).copyWith(
          isLoading: false,
          error: e.toString(),
        ),
      );
    }
  }

  Future<void> setBucket(String? bucket) async {
    final currentState = state.value!;
    _logger.info('Selected S3 bucket: ${bucket ?? "<none>"}');
    state = AsyncData(
      currentState.copyWith(
        selectedBucket: bucket,
        isLoading: true,
        error: null,
      ),
    );
    try {
      state = AsyncData(await _fetchFiles(state.value!));
    } catch (e) {
      _logger.error('Failed to load S3 bucket $bucket: $e');
      state = AsyncData(
        state.value!.copyWith(isLoading: false, error: e.toString()),
      );
    }
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
    state = AsyncData(
      state.value!.copyWith(
        selectedFilePaths: files.map((f) => f.path).toSet(),
      ),
    );
  }

  void clearSelection() {
    state = AsyncData(state.value!.copyWith(selectedFilePaths: {}));
  }

  Future<void> setTags(List<Tag> tags) async {
    _logger.debug(
      'Updating S3 tag filter: ${tags.map((t) => t.name).toList()}',
    );
    state = AsyncData(
      state.value!.copyWith(selectedTags: tags, isLoading: true),
    );
    try {
      state = AsyncData(await _fetchFiles(state.value!));
    } catch (e) {
      _logger.error('Failed to update S3 tag filter: $e');
      state = AsyncData(
        state.value!.copyWith(isLoading: false, error: e.toString()),
      );
    }
  }

  Future<void> setSession(Session? session) async {
    _logger.debug('Updating S3 session filter: ${session?.id ?? "all"}');
    state = AsyncData(
      state.value!.copyWith(selectedSession: session, isLoading: true),
    );
    try {
      state = AsyncData(await _fetchFiles(state.value!));
    } catch (e) {
      _logger.error('Failed to update S3 session filter: $e');
      state = AsyncData(
        state.value!.copyWith(isLoading: false, error: e.toString()),
      );
    }
  }

  Future<void> deleteSelected() async {
    final currentState = state.value!;
    _logger.warn(
      'Deleting ${currentState.selectedFilePaths.length} S3 object(s) from ${currentState.selectedBucket ?? "<unknown bucket>"}',
    );
    state = AsyncData(currentState.copyWith(isDeleting: true));

    final config = ref.read(appConfigProvider);
    final client = ApiClient(config);

    try {
      for (final path in currentState.selectedFilePaths) {
        final file = currentState.files.firstWhere((f) => f.path == path);
        await client.delete(
          '${config.ragAdminApiUrl}/api/s3/buckets/${file.bucket}/${file.path}',
        );
      }
      await refresh();
    } catch (e) {
      _logger.error('S3 delete failed: $e');
      state = AsyncData(
        state.value!.copyWith(isDeleting: false, error: e.toString()),
      );
    }
  }
}
