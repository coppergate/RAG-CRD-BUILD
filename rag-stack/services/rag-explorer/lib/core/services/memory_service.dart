import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_config.dart';
import '../../app_config_provider.dart';
import 'log_service.dart';
import '../../features/memory/memory_contracts.dart';

final memoryServiceProvider = Provider((ref) {
  final config = ref.watch(appConfigProvider);
  final dio = ref.watch(dioProvider);
  final logger = ref.watch(logProvider.notifier);
  return MemoryService(dio, config, logger);
});

class MemoryService {
  final Dio _dio;
  final AppConfig _config;
  final LogNotifier _logger;

  MemoryService(this._dio, this._config, this._logger);

  Future<List<MemoryRecord>> getMemoryItems(int sessionId) async {
    _logger.debug('Fetching memory items for session $sessionId');
    try {
      final response = await _dio.get(
        '${_config.memoryUrl}/items',
        queryParameters: {'session_id': sessionId},
      );
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is List) {
          return data
              .whereType<Map>()
              .map(
                (item) => MemoryRecord.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList();
        }
        if (data is Map<String, dynamic> && data['items'] is List) {
          return (data['items'] as List)
              .whereType<Map>()
              .map(
                (item) => MemoryRecord.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList();
        }
      }
      return [];
    } catch (e) {
      _logger.error('Error fetching memory items: $e');
      return [];
    }
  }

  Future<bool> writeMemory(MemoryWriteRequest request) async {
    _logger.info('Writing memory item');
    try {
      final response = await _dio.post(
        '${_config.memoryUrl}/items',
        data: request.toJson(),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      _logger.error('Error writing memory: $e');
      return false;
    }
  }

  Future<MemoryPack?> retrieveMemory(MemoryRetrieveRequest request) async {
    _logger.info('Retrieving memory for session ${request.scope.sessionId}');
    try {
      final response = await _dio.post(
        '${_config.memoryUrl}/retrieve',
        data: request.toJson(),
      );
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return MemoryPack.fromJson(data);
        }
        if (data is Map) {
          return MemoryPack.fromJson(
            data.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      }
      return null;
    } catch (e) {
      _logger.error('Error retrieving memory: $e');
      return null;
    }
  }
}
