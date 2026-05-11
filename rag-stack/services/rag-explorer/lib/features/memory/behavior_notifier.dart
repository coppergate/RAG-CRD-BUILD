import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/models/behavioral_rule.dart';
import '../../core/services/behavior_service.dart';

part 'behavior_notifier.freezed.dart';
part 'behavior_notifier.g.dart';

@freezed
class BehaviorState with _$BehaviorState {
  const factory BehaviorState({
    @Default([]) List<BehavioralRule> rules,
    @Default([]) List<ActionIdentifier> identifiers,
    @Default(false) bool isLoading,
    String? error,
  }) = _BehaviorState;
}

@riverpod
class BehaviorNotifier extends _$BehaviorNotifier {
  @override
  FutureOr<BehaviorState> build() async {
    final service = ref.watch(behaviorServiceProvider);
    final rules = await service.getRules();
    final identifiers = await service.getIdentifiers();
    return BehaviorState(rules: rules, identifiers: identifiers);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    final service = ref.read(behaviorServiceProvider);
    final rules = await service.getRules();
    final identifiers = await service.getIdentifiers();
    state = AsyncData(BehaviorState(rules: rules, identifiers: identifiers));
  }

  Future<void> acceptRule(int ruleId) async {
    final service = ref.read(behaviorServiceProvider);
    final success = await service.updateRuleStatus(ruleId, 'ACTIVE');
    if (success) {
      await refresh();
    }
  }

  Future<void> rejectRule(int ruleId) async {
    final service = ref.read(behaviorServiceProvider);
    final success = await service.updateRuleStatus(ruleId, 'REJECTED');
    if (success) {
      await refresh();
    }
  }

  Future<void> learnRule(String content, String actionType) async {
    final service = ref.read(behaviorServiceProvider);
    final success = await service.learnRule(content, actionType);
    if (success) {
      await refresh();
    }
  }
}
