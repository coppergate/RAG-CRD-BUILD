import 'package:freezed_annotation/freezed_annotation.dart';

part 'memory_pack.freezed.dart';
part 'memory_pack.g.dart';

@freezed
class MemoryPack with _$MemoryPack {
  const factory MemoryPack({
    required List<dynamic> memories,
    required Map<String, dynamic> metadata,
  }) = _MemoryPack;

  factory MemoryPack.fromJson(Map<String, dynamic> json) => _$MemoryPackFromJson(json);
}
