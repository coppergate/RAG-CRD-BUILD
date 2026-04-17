import 'package:dio/dio.dart';
import 'dart:typed_data';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/tag.dart';
import '../../config/app_config.dart';
import '../../app_config_provider.dart';
import 'log_service.dart';

part 'ingestion_service.g.dart';

@riverpod
class IngestionService extends _$IngestionService {
  late Dio _dio;
  late AppConfig _config;
  late LogNotifier _logger;

  @override
  FutureOr<void> build() {
    _dio = ref.watch(dioProvider);
    _config = ref.watch(appConfigProvider);
    _logger = ref.read(logProvider.notifier);
  }

  Future<List<String>> getBuckets() async {
    _logger.debug('Fetching S3 buckets');
    try {
      final response = await _dio.get('${_config.ragAdminApiUrl}/api/s3/buckets');
      if (response.statusCode == 200) {
        return List<String>.from(response.data);
      }
      return [];
    } catch (e) {
      _logger.error('Error fetching buckets: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getObjects(String bucket, {String prefix = ''}) async {
    _logger.debug('Fetching objects for bucket: $bucket, prefix: $prefix');
    try {
      final response = await _dio.get(
        '${_config.ragAdminApiUrl}/api/s3/buckets/$bucket',
        queryParameters: {'prefix': prefix},
      );
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      _logger.error('Error fetching objects: $e');
      return [];
    }
  }

  Future<List<Tag>> getTags() async {
    _logger.debug('Fetching tags from database');
    try {
      final response = await _dio.get('${_config.ragAdminApiUrl}/api/db/tags');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((e) => Tag.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      _logger.error('Error fetching tags: $e');
      return [];
    }
  }

  Future<Tag?> createTag(String name) async {
    _logger.info('Creating new tag: $name');
    try {
      final response = await _dio.post(
        '${_config.ragAdminApiUrl}/api/db/tags',
        data: {'name': name},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return Tag.fromJson(response.data);
      }
      return null;
    } catch (e) {
      _logger.error('Error creating tag: $e');
      return null;
    }
  }

  Future<bool> deleteTag(String id) async {
    _logger.warn('Deleting tag: $id');
    try {
      final response = await _dio.delete('${_config.ragAdminApiUrl}/api/db/tags/$id');
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      _logger.error('Error deleting tag: $e');
      return false;
    }
  }

  Future<bool> uploadFile(String bucket, String key, Uint8List bytes) async {
    _logger.info('Uploading file to S3: $bucket/$key');
    try {
      final response = await _dio.put(
        '${_config.ragAdminApiUrl}/api/s3/buckets/$bucket/$key',
        data: Stream.fromIterable([bytes]),
        options: Options(
          headers: {
            Headers.contentLengthHeader: bytes.length,
          },
        ),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.info('File uploaded successfully: $key');
        return true;
      }
      _logger.error('Failed to upload file: ${response.statusCode}');
      return false;
    } catch (e) {
      _logger.error('Error uploading file: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> triggerIngest({
    required String bucketName,
    required List<String> tagIds,
    String prefix = '',
    bool forceReingest = false,
  }) async {
    _logger.info('Triggering ingestion for bucket: $bucketName, tags: $tagIds');
    try {
      final response = await _dio.post(
        '${_config.ragAdminApiUrl}/api/ingest/ingest',
        data: {
          'bucket_name': bucketName,
          'prefix': prefix,
          'tag_ids': tagIds,
          'force_reingest': forceReingest,
        },
      );
      if (response.statusCode == 200 || response.statusCode == 202) {
        _logger.info('Ingestion triggered successfully: ${response.data}');
        return response.data;
      }
      _logger.error('Failed to trigger ingestion: ${response.statusCode}');
      return {'error': 'Failed to trigger ingestion', 'status': response.statusCode};
    } catch (e) {
      _logger.error('Error triggering ingestion: $e');
      return {'error': e.toString()};
    }
  }
}
