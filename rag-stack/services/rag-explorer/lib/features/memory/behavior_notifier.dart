import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/models/behavioral_rule.dart';
import '../../core/services/behavior_service.dart';
import '../../core/services/log_service.dart';

part 'behavior_notifier.freezed.dart';
part 'behavior_notifier.g.dart';

@freezed
abstract class BehaviorState with _$BehaviorState {
  const factory BehaviorState({
    @Default([]) List<BehavioralRule> rules,
    @Default([]) List<ActionIdentifier> identifiers,
    @Default(false) bool isLoading,
    String? error,
  }) = _BehaviorState;
}

@riverpod
class BehaviorNotifier extends _$BehaviorNotifier {
  LogNotifier get _logger => ref.read(logProvider.notifier);

  @override
  FutureOr<BehaviorState> build() async {
    final service = ref.watch(behaviorServiceProvider);
    _logger.debug('Building behavioral rules state');
    final rules = await service.getRules();
    final identifiers = await service.getIdentifiers();
    return BehaviorState(rules: rules, identifiers: identifiers);
  }

  Future<void> refresh() async {
    _logger.info('Refreshing behavioral rules');
    state = const AsyncLoading();
    final service = ref.read(behaviorServiceProvider);
    final rules = await service.getRules();
    final identifiers = await service.getIdentifiers();
    state = AsyncData(BehaviorState(rules: rules, identifiers: identifiers));
  }

  Future<void> acceptRule(int ruleId) async {
    final service = ref.read(behaviorServiceProvider);
    _logger.info('Accepting behavioral rule: $ruleId');
    final success = await service.updateRuleStatus(ruleId, 'ACTIVE');
    if (success) {
      await refresh();
    }
  }

  Future<void> rejectRule(int ruleId) async {
    final service = ref.read(behaviorServiceProvider);
    _logger.warn('Rejecting behavioral rule: $ruleId');
    final success = await service.updateRuleStatus(ruleId, 'REJECTED');
    if (success) {
      await refresh();
    }
  }

  Future<void> deleteRule(int ruleId) async {
    await rejectRule(ruleId);
  }

  Future<void> learnRule(String content, String actionType) async {
    final service = ref.read(behaviorServiceProvider);
    _logger.info('Learning rule for action type: $actionType');
    final success = await service.learnRule(content, actionType);
    if (success) {
      await refresh();
    }
  }
}
