// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'db_op_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DbOpMessage _$DbOpMessageFromJson(Map<String, dynamic> json) => _DbOpMessage(
  operation: json['operation'] as String,
  table: json['table'] as String,
  data: json['data'] as Map<String, dynamic>,
  condition: json['condition'] as String?,
  timestamp: json['timestamp'] == null
      ? null
      : DateTime.parse(json['timestamp'] as String),
);

Map<String, dynamic> _$DbOpMessageToJson(_DbOpMessage instance) =>
    <String, dynamic>{
      'operation': instance.operation,
      'table': instance.table,
      'data': instance.data,
      'condition': instance.condition,
      'timestamp': instance.timestamp?.toIso8601String(),
    };
