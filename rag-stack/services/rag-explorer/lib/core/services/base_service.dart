import 'package:dio/dio.dart';
import '../../config/app_config.dart';
import '../utils/http_utils.dart';
import 'log_service.dart';

abstract class BaseService {
  final Dio dio;
  final AppConfig config;
  final LogNotifier logger;

  const BaseService(this.dio, this.config, this.logger);

  /// GET a list of [T]. Returns empty list on any failure.
  Future<List<T>> getList<T>(
    String url,
    T Function(dynamic) parse, {
    Map<String, dynamic>? queryParams,
    String? logLabel,
  }) async {
    final label = logLabel ?? url;
    try {
      final r = await dio.get(url, queryParameters: queryParams);
      if (r.isSuccess) {
        final List<dynamic> data = r.data is List ? r.data : [];
        return data.map(parse).toList();
      }
      logger.warn('GET $label failed: ${r.statusCode}');
      return [];
    } catch (e) {
      logger.error('GET $label error: $e');
      return [];
    }
  }

  /// GET a single [T]. Returns null on any failure.
  Future<T?> getOne<T>(
    String url,
    T Function(dynamic) parse, {
    Map<String, dynamic>? queryParams,
    String? logLabel,
  }) async {
    final label = logLabel ?? url;
    try {
      final r = await dio.get(url, queryParameters: queryParams);
      if (r.isSuccess && r.data != null) return parse(r.data);
      logger.warn('GET $label failed: ${r.statusCode}');
      return null;
    } catch (e) {
      logger.error('GET $label error: $e');
      return null;
    }
  }

  /// POST and return a parsed [T]. Returns null on failure.
  Future<T?> postOne<T>(
    String url,
    dynamic data,
    T Function(dynamic) parse, {
    String? logLabel,
  }) async {
    final label = logLabel ?? url;
    try {
      final r = await dio.post(url, data: data);
      if (r.isSuccess && r.data != null) return parse(r.data);
      logger.warn('POST $label failed: ${r.statusCode}');
      return null;
    } catch (e) {
      logger.error('POST $label error: $e');
      return null;
    }
  }

  /// POST with no meaningful response body. Returns true on success.
  Future<bool> postVoid(
    String url,
    dynamic data, {
    String? logLabel,
  }) async {
    final label = logLabel ?? url;
    try {
      final r = await dio.post(url, data: data);
      if (r.isSuccess) return true;
      logger.warn('POST $label failed: ${r.statusCode}');
      return false;
    } catch (e) {
      logger.error('POST $label error: $e');
      return false;
    }
  }

  /// DELETE a resource. Returns true on success.
  Future<bool> deleteOne(String url, {String? logLabel}) async {
    final label = logLabel ?? url;
    try {
      final r = await dio.delete(url);
      if (r.isSuccess) return true;
      logger.warn('DELETE $label failed: ${r.statusCode}');
      return false;
    } catch (e) {
      logger.error('DELETE $label error: $e');
      return false;
    }
  }
}
