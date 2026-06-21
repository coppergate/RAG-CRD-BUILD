import 'package:dio/dio.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tag.dart';
import '../../app_config_provider.dart';
import '../utils/http_utils.dart';
import 'base_service.dart';
import 'log_service.dart';

final ingestionServiceProvider = Provider((ref) {
  final config = ref.watch(appConfigProvider);
  final dio = ref.watch(dioProvider);
  final logger = ref.watch(logProvider.notifier);
  return IngestionService(dio, config, logger);
});

class IngestionService extends BaseService {
  IngestionService(super.dio, super.config, super.logger);

  Future<List<String>> getBuckets() async {
    logger.debug('Fetching S3 buckets');
    try {
      final r = await dio.get('${config.ragAdminApiUrl}/api/s3/buckets');
      if (!r.isSuccess) return [];
      final List<dynamic> data = r.data is List ? r.data : [];
      return data
          .whereType<Map>()
          .map((e) => (e['Name'] ?? e['name'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      logger.error('Error fetching buckets: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getObjects(
    String bucket, {
    String prefix = '',
  }) async {
    logger.debug('Fetching objects for bucket: $bucket, prefix: $prefix');
    try {
      final r = await dio.get(
        '${config.ragAdminApiUrl}/api/s3/buckets/$bucket',
        queryParameters: {'prefix': prefix},
      );
      if (!r.isSuccess) return [];
      return List<Map<String, dynamic>>.from(r.data);
    } catch (e) {
      logger.error('Error fetching objects: $e');
      return [];
    }
  }

  Future<List<Tag>> getTags() async {
    logger.debug('Fetching tags from database');
    try {
      final r = await dio.get('${config.ragAdminApiUrl}/api/db/tags');
      if (!r.isSuccess) return [];
      dynamic data = r.data;
      if (data is String) {
        logger.warn('Backend returned string for tags, attempting to decode JSON.');
        try {
          data = json.decode(data);
        } catch (e) {
          logger.error('Failed to decode tags string: $e');
          return [];
        }
      }
      if (data is! List) {
        logger.error('Tags data is not a list: ${data.runtimeType}');
        return [];
      }
      return data.map((e) => Tag.fromJson(asStringMap(e))).toList();
    } catch (e) {
      logger.error('Error fetching tags: $e');
      return [];
    }
  }

  Future<Tag?> createTag(String name) async {
    logger.info('Creating new tag: $name');
    try {
      final r = await dio.post(
        '${config.ragAdminApiUrl}/api/db/tags',
        data: {'name': name},
      );
      if (!r.isSuccess) return null;
      dynamic data = r.data;
      if (data is String) {
        logger.warn('Backend returned string for createTag, attempting to decode JSON.');
        try {
          data = json.decode(data);
        } catch (e) {
          logger.error('Failed to decode created tag string: $e');
          return null;
        }
      }
      return Tag.fromJson(asStringMap(data));
    } catch (e) {
      logger.error('Error creating tag: $e');
      return null;
    }
  }

  Future<bool> deleteTag(int id) {
    logger.warn('Deleting tag: $id');
    return deleteOne('${config.ragAdminApiUrl}/api/db/tags/$id', logLabel: 'tag $id');
  }

  Future<List<String>> getAllowedExtensions() async {
    logger.debug('Fetching allowed extensions from ingestion service');
    try {
      final r = await dio.get('${config.ragAdminApiUrl}/api/ingest/extensions');
      if (!r.isSuccess) return [];
      final List<dynamic> extensions = r.data['extensions'];
      return extensions.cast<String>();
    } catch (e) {
      logger.error('Error fetching extensions: $e');
      return [];
    }
  }

  Future<bool> uploadFile(String bucket, String key, Uint8List bytes) async {
    logger.info('Uploading file to S3: $bucket/$key');
    try {
      final r = await dio.put(
        '${config.ragAdminApiUrl}/api/s3/buckets/$bucket/$key',
        data: Stream.fromIterable([bytes]),
        options: Options(headers: {Headers.contentLengthHeader: bytes.length}),
      );
      if (r.isSuccess) {
        logger.info('File uploaded successfully: $key');
        return true;
      }
      logger.error('Failed to upload file: ${r.statusCode}');
      return false;
    } catch (e) {
      logger.error('Error uploading file: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> triggerIngest({
    required String bucketName,
    required List<int> tagIds,
    String prefix = '',
    bool forceReingest = false,
    String embeddingModel = 'all-minilm:l6-v2',
  }) async {
    logger.info(
      'Triggering ingestion for bucket: $bucketName, tags: $tagIds, model: $embeddingModel',
    );
    try {
      final r = await dio.post(
        '${config.ragAdminApiUrl}/api/ingest/ingest',
        data: {
          'bucket_name': bucketName,
          'prefix': prefix,
          'tag_ids': tagIds,
          'force_reingest': forceReingest,
          'embedding_model': embeddingModel,
        },
      );
      if (r.isSuccess) {
        logger.info('Ingestion triggered successfully: ${r.data}');
        return r.data;
      }
      logger.error('Failed to trigger ingestion: ${r.statusCode}');
      return {'error': 'Failed to trigger ingestion', 'status': r.statusCode};
    } catch (e) {
      logger.error('Error triggering ingestion: $e');
      return {'error': e.toString()};
    }
  }

  Future<bool> deleteObject(String bucket, String key) {
    logger.warn('Deleting object from S3: $bucket/$key');
    return deleteOne(
      '${config.ragAdminApiUrl}/api/s3/buckets/$bucket/$key',
      logLabel: 'S3 $bucket/$key',
    );
  }

  Future<String?> getObjectContent(String bucket, String key) {
    logger.debug('Fetching object content: $bucket/$key');
    return getOne(
      '${config.ragAdminApiUrl}/api/s3/buckets/$bucket/$key',
      (data) => data.toString(),
      logLabel: '$bucket/$key',
    );
  }
}
