// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Session _$SessionFromJson(Map<String, dynamic> json) => _Session(
  id: json['id'] as String,
  name: json['name'] as String?,
  description: json['description'] as String?,
  createdAt: DateTime.parse(json['created_at'] as String),
  lastActiveAt: DateTime.parse(json['last_active_at'] as String),
  metadata: json['metadata'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$SessionToJson(_Session instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'description': instance.description,
  'created_at': instance.createdAt.toIso8601String(),
  'last_active_at': instance.lastActiveAt.toIso8601String(),
  'metadata': instance.metadata,
};
