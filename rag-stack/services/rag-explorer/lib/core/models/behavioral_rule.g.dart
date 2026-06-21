// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'behavioral_rule.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_BehavioralRule _$BehavioralRuleFromJson(Map<String, dynamic> json) =>
    _BehavioralRule(
      id: (json['id'] as num).toInt(),
      actionType: json['actionType'] as String,
      category: json['category'] as String?,
      state: json['state'] as String,
      ruleContent: json['ruleContent'] as String,
      priority: (json['priority'] as num).toInt(),
      isActive: json['isActive'] as bool,
      scope: json['scope'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$BehavioralRuleToJson(_BehavioralRule instance) =>
    <String, dynamic>{
      'id': instance.id,
      'actionType': instance.actionType,
      'category': instance.category,
      'state': instance.state,
      'ruleContent': instance.ruleContent,
      'priority': instance.priority,
      'isActive': instance.isActive,
      'scope': instance.scope,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };

_ActionIdentifier _$ActionIdentifierFromJson(Map<String, dynamic> json) =>
    _ActionIdentifier(
      actionType: json['actionType'] as String,
      description: json['description'] as String,
      category: json['category'] as String,
    );

Map<String, dynamic> _$ActionIdentifierToJson(_ActionIdentifier instance) =>
    <String, dynamic>{
      'actionType': instance.actionType,
      'description': instance.description,
      'category': instance.category,
    };
