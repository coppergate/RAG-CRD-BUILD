import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_config_provider.dart';
import '../utils/http_utils.dart';
import 'base_service.dart';
import 'log_service.dart';
import '../../features/memory/memory_contracts.dart';

final memoryServiceProvider = Provider((ref) {
  final config = ref.watch(appConfigProvider);
  final dio = ref.watch(dioProvider);
  final logger = ref.watch(logProvider.notifier);
  return MemoryService(dio, config, logger);
});

class MemoryService extends BaseService {
  MemoryService(super.dio, super.config, super.logger);

  Future<List<MemoryRecord>> getMemoryItems(int sessionId) async {
    logger.debug('Fetching memory items for session $sessionId');
    try {
      final r = await dio.get(
        '${config.memoryUrl}/items',
        queryParameters: {'session_id': sessionId},
      );
      if (!r.isSuccess) return [];
      final data = r.data;
      final List rawItems = data is List
          ? data
          : (data is Map<String, dynamic> && data['items'] is List)
              ? data['items'] as List
              : [];
      return rawItems
          .whereType<Map>()
          .map((item) => MemoryRecord.fromJson(asStringMap(item)))
          .toList();
    } catch (e) {
      logger.error('Error fetching memory items: $e');
      return [];
    }
  }

  Future<bool> writeMemory(MemoryWriteRequest request) {
    logger.info('Writing memory item');
    return postVoid(
      '${config.memoryUrl}/items',
      request.toJson(),
      logLabel: 'write memory',
    );
  }

  Future<MemoryPack?> retrieveMemory(MemoryRetrieveRequest request) {
    logger.info('Retrieving memory for session ${request.scope.sessionId}');
    return postOne(
      '${config.memoryUrl}/retrieve',
      request.toJson(),
      (data) => MemoryPack.fromJson(asStringMap(data)),
      logLabel: 'retrieve memory',
    );
  }
}
