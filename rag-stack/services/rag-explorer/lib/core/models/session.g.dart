// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Session _$SessionFromJson(Map<String, dynamic> json) => _Session(
  createdAt: DateTime.parse(json['created_at'] as String),
  description: json['description'] as String?,
  id: (json['id'] as num?)?.toInt() ?? 0,
  lastActiveAt: DateTime.parse(json['last_active_at'] as String),
  metadata: json['metadata'] as Map<String, dynamic>?,
  name: json['name'] as String?,
  tags: (json['tags'] as List<dynamic>?)
      ?.map((e) => Tag.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$SessionToJson(_Session instance) => <String, dynamic>{
  'created_at': instance.createdAt.toIso8601String(),
  'description': instance.description,
  'id': instance.id,
  'last_active_at': instance.lastActiveAt.toIso8601String(),
  'metadata': instance.metadata,
  'name': instance.name,
  'tags': instance.tags,
};
