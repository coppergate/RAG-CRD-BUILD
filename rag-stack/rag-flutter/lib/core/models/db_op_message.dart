import 'package:freezed_annotation/freezed_annotation.dart';

part 'db_op_message.freezed.dart';
part 'db_op_message.g.dart';

@freezed
class DbOpMessage with _$DbOpMessage {
  const factory DbOpMessage({
    required String operation,
    required String table,
    required Map<String, dynamic> data,
    String? condition,
    DateTime? timestamp,
  }) = _DbOpMessage;

  factory DbOpMessage.fromJson(Map<String, dynamic> json) => _$DbOpMessageFromJson(json);
}
