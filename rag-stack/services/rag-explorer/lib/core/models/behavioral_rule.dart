import 'package:freezed_annotation/freezed_annotation.dart';

part 'behavioral_rule.freezed.dart';
part 'behavioral_rule.g.dart';

@freezed
class BehavioralRule with _$BehavioralRule {
  const factory BehavioralRule({
    required int id,
    required String actionType,
    String? category,
    required String state,
    required String ruleContent,
    required int priority,
    required bool isActive,
    required String scope,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _BehavioralRule;

  factory BehavioralRule.fromJson(Map<String, dynamic> json) => _$BehavioralRuleFromJson(json);
}

@freezed
class ActionIdentifier with _$ActionIdentifier {
  const factory ActionIdentifier({
    required String actionType,
    required String description,
    required String category,
  }) = _ActionIdentifier;

  factory ActionIdentifier.fromJson(Map<String, dynamic> json) => _$ActionIdentifierFromJson(json);
}
