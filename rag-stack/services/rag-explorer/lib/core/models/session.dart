import 'package:freezed_annotation/freezed_annotation.dart';

import 'tag.dart';

part 'session.freezed.dart';
part 'session.g.dart';

@freezed
abstract class Session with _$Session {
  const factory Session({
    @JsonKey(name: 'created_at') required DateTime createdAt,
    String? description,
    @Default(0) required int id,
    @JsonKey(name: 'last_active_at') required DateTime lastActiveAt,
    Map<String, dynamic>? metadata,
    String? name,
    List<Tag>? tags,
  }) = _Session;

  factory Session.fromJson(Map<String, dynamic> json) => _$SessionFromJson(json);
}
