import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_config.dart';
import '../../app_config_provider.dart';
import '../models/behavioral_rule.dart';
import 'log_service.dart';

final behaviorServiceProvider = Provider((ref) {
  final config = ref.watch(appConfigProvider);
  final dio = ref.watch(dioProvider);
  final logger = ref.watch(logProvider.notifier);
  return BehaviorService(dio, config, logger);
});

class BehaviorService {
  final Dio _dio;
  final AppConfig _config;
  final LogNotifier _logger;

  BehaviorService(this._dio, this._config, this._logger);

  Future<List<BehavioralRule>> getRules() async {
    _logger.debug('Fetching behavioral rules');
    try {
      final response = await _dio.get('${_config.behaviorUrl}/rules');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((e) => BehavioralRule.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      _logger.error('Error fetching behavioral rules: $e');
      return [];
    }
  }

  Future<bool> updateRuleStatus(int ruleId, String status) async {
    _logger.info('Updating rule $ruleId status to $status');
    try {
      final response = await _dio.post('${_config.behaviorUrl}/rules/$ruleId/status', data: {'status': status});
      return response.statusCode == 200;
    } catch (e) {
      _logger.error('Error updating rule status: $e');
      return false;
    }
  }

  Future<bool> learnRule(String content, String actionType) async {
    _logger.info('Learning new rule for action $actionType');
    try {
      final response = await _dio.post('${_config.behaviorUrl}/learn', data: {
        'content': content,
        'action_type': actionType,
      });
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      _logger.error('Error learning rule: $e');
      return false;
    }
  }

  Future<List<ActionIdentifier>> getIdentifiers() async {
    _logger.debug('Fetching action identifiers');
    try {
      final response = await _dio.get('${_config.behaviorUrl}/identifiers');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((e) => ActionIdentifier.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      _logger.error('Error fetching identifiers: $e');
      return [];
    }
  }
}
