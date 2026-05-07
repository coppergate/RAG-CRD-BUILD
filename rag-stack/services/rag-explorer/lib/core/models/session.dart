import 'package:freezed_annotation/freezed_annotation.dart';

import 'tag.dart';

part 'session.freezed.dart';
part 'session.g.dart';

@freezed
abstract class Session with _$Session {
  const factory Session({
    required int id,
    String? name,
    String? description,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'last_active_at') required DateTime lastActiveAt,
    List<Tag>? tags,
    Map<String, dynamic>? metadata,
  }) = _Session;

  factory Session.fromJson(Map<String, dynamic> json) => _$SessionFromJson(json);
}
