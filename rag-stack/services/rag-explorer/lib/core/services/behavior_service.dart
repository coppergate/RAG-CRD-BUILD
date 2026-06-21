import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_config_provider.dart';
import '../models/behavioral_rule.dart';
import 'base_service.dart';
import 'log_service.dart';

final behaviorServiceProvider = Provider((ref) {
  final config = ref.watch(appConfigProvider);
  final dio = ref.watch(dioProvider);
  final logger = ref.watch(logProvider.notifier);
  return BehaviorService(dio, config, logger);
});

class BehaviorService extends BaseService {
  BehaviorService(super.dio, super.config, super.logger);

  Future<List<BehavioralRule>> getRules() {
    logger.debug('Fetching behavioral rules');
    return getList(
      '${config.behaviorUrl}/rules',
      (e) => BehavioralRule.fromJson(e),
      logLabel: 'behavioral rules',
    );
  }

  Future<bool> updateRuleStatus(int ruleId, String status) {
    logger.info('Updating rule $ruleId status to $status');
    return postVoid(
      '${config.behaviorUrl}/rules/$ruleId/status',
      {'status': status},
      logLabel: 'rule $ruleId status',
    );
  }

  Future<bool> learnRule(String content, String actionType) {
    logger.info('Learning new rule for action $actionType');
    return postVoid(
      '${config.behaviorUrl}/learn',
      {'content': content, 'action_type': actionType},
      logLabel: 'learn rule',
    );
  }

  Future<List<ActionIdentifier>> getIdentifiers() {
    logger.debug('Fetching action identifiers');
    return getList(
      '${config.behaviorUrl}/identifiers',
      (e) => ActionIdentifier.fromJson(e),
      logLabel: 'action identifiers',
    );
  }
}
