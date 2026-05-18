import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_config.dart';
import '../../app_config_provider.dart';
import '../models/memory_pack.dart';
import '../models/memory_retrieve_request.dart';
import '../models/memory_write_request.dart';
import 'log_service.dart';

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

  Future<List<dynamic>> getMemoryItems(int sessionId) async {
    _logger.debug('Fetching memory items for session $sessionId');
    try {
      final response = await _dio.get('${_config.memoryUrl}/items', queryParameters: {'session_id': sessionId});
      if (response.statusCode == 200) {
        return response.data as List<dynamic>;
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
      final response = await _dio.post('${_config.memoryUrl}/items', data: request.toJson());
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      _logger.error('Error writing memory: $e');
      return false;
    }
  }

  Future<MemoryPack?> retrieveMemory(MemoryRetrieveRequest request) async {
    _logger.info('Retrieving memory for session ${request.sessionId}');
    try {
      final response = await _dio.post('${_config.memoryUrl}/retrieve', data: request.toJson());
      if (response.statusCode == 200) {
        return MemoryPack.fromJson(response.data);
      }
      return null;
    } catch (e) {
      _logger.error('Error retrieving memory: $e');
      return null;
    }
  }
}
