// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'metrics.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$QdrantStats {

 String get status;@JsonKey(name: 'points_count') int get pointsCount;@JsonKey(name: 'segments_count') int get segmentsCount;@JsonKey(name: 'indexed_vectors_count') int? get indexedVectorsCount;@JsonKey(name: 'payload_schema') Map<String, dynamic>? get payloadSchema;
/// Create a copy of QdrantStats
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QdrantStatsCopyWith<QdrantStats> get copyWith => _$QdrantStatsCopyWithImpl<QdrantStats>(this as QdrantStats, _$identity);

  /// Serializes this QdrantStats to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QdrantStats&&(identical(other.status, status) || other.status == status)&&(identical(other.pointsCount, pointsCount) || other.pointsCount == pointsCount)&&(identical(other.segmentsCount, segmentsCount) || other.segmentsCount == segmentsCount)&&(identical(other.indexedVectorsCount, indexedVectorsCount) || other.indexedVectorsCount == indexedVectorsCount)&&const DeepCollectionEquality().equals(other.payloadSchema, payloadSchema));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,status,pointsCount,segmentsCount,indexedVectorsCount,const DeepCollectionEquality().hash(payloadSchema));

@override
String toString() {
  return 'QdrantStats(status: $status, pointsCount: $pointsCount, segmentsCount: $segmentsCount, indexedVectorsCount: $indexedVectorsCount, payloadSchema: $payloadSchema)';
}


}

/// @nodoc
abstract mixin class $QdrantStatsCopyWith<$Res>  {
  factory $QdrantStatsCopyWith(QdrantStats value, $Res Function(QdrantStats) _then) = _$QdrantStatsCopyWithImpl;
@useResult
$Res call({
 String status,@JsonKey(name: 'points_count') int pointsCount,@JsonKey(name: 'segments_count') int segmentsCount,@JsonKey(name: 'indexed_vectors_count') int? indexedVectorsCount,@JsonKey(name: 'payload_schema') Map<String, dynamic>? payloadSchema
});




}
/// @nodoc
class _$QdrantStatsCopyWithImpl<$Res>
    implements $QdrantStatsCopyWith<$Res> {
  _$QdrantStatsCopyWithImpl(this._self, this._then);

  final QdrantStats _self;
  final $Res Function(QdrantStats) _then;

/// Create a copy of QdrantStats
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? pointsCount = null,Object? segmentsCount = null,Object? indexedVectorsCount = freezed,Object? payloadSchema = freezed,}) {
  return _then(_self.copyWith(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,pointsCount: null == pointsCount ? _self.pointsCount : pointsCount // ignore: cast_nullable_to_non_nullable
as int,segmentsCount: null == segmentsCount ? _self.segmentsCount : segmentsCount // ignore: cast_nullable_to_non_nullable
as int,indexedVectorsCount: freezed == indexedVectorsCount ? _self.indexedVectorsCount : indexedVectorsCount // ignore: cast_nullable_to_non_nullable
as int?,payloadSchema: freezed == payloadSchema ? _self.payloadSchema : payloadSchema // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}

}


/// Adds pattern-matching-related methods to [QdrantStats].
extension QdrantStatsPatterns on QdrantStats {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QdrantStats value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QdrantStats() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QdrantStats value)  $default,){
final _that = this;
switch (_that) {
case _QdrantStats():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QdrantStats value)?  $default,){
final _that = this;
switch (_that) {
case _QdrantStats() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String status, @JsonKey(name: 'points_count')  int pointsCount, @JsonKey(name: 'segments_count')  int segmentsCount, @JsonKey(name: 'indexed_vectors_count')  int? indexedVectorsCount, @JsonKey(name: 'payload_schema')  Map<String, dynamic>? payloadSchema)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QdrantStats() when $default != null:
return $default(_that.status,_that.pointsCount,_that.segmentsCount,_that.indexedVectorsCount,_that.payloadSchema);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String status, @JsonKey(name: 'points_count')  int pointsCount, @JsonKey(name: 'segments_count')  int segmentsCount, @JsonKey(name: 'indexed_vectors_count')  int? indexedVectorsCount, @JsonKey(name: 'payload_schema')  Map<String, dynamic>? payloadSchema)  $default,) {final _that = this;
switch (_that) {
case _QdrantStats():
return $default(_that.status,_that.pointsCount,_that.segmentsCount,_that.indexedVectorsCount,_that.payloadSchema);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String status, @JsonKey(name: 'points_count')  int pointsCount, @JsonKey(name: 'segments_count')  int segmentsCount, @JsonKey(name: 'indexed_vectors_count')  int? indexedVectorsCount, @JsonKey(name: 'payload_schema')  Map<String, dynamic>? payloadSchema)?  $default,) {final _that = this;
switch (_that) {
case _QdrantStats() when $default != null:
return $default(_that.status,_that.pointsCount,_that.segmentsCount,_that.indexedVectorsCount,_that.payloadSchema);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _QdrantStats implements QdrantStats {
  const _QdrantStats({required this.status, @JsonKey(name: 'points_count') required this.pointsCount, @JsonKey(name: 'segments_count') required this.segmentsCount, @JsonKey(name: 'indexed_vectors_count') this.indexedVectorsCount, @JsonKey(name: 'payload_schema') final  Map<String, dynamic>? payloadSchema}): _payloadSchema = payloadSchema;
  factory _QdrantStats.fromJson(Map<String, dynamic> json) => _$QdrantStatsFromJson(json);

@override final  String status;
@override@JsonKey(name: 'points_count') final  int pointsCount;
@override@JsonKey(name: 'segments_count') final  int segmentsCount;
@override@JsonKey(name: 'indexed_vectors_count') final  int? indexedVectorsCount;
 final  Map<String, dynamic>? _payloadSchema;
@override@JsonKey(name: 'payload_schema') Map<String, dynamic>? get payloadSchema {
  final value = _payloadSchema;
  if (value == null) return null;
  if (_payloadSchema is EqualUnmodifiableMapView) return _payloadSchema;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of QdrantStats
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QdrantStatsCopyWith<_QdrantStats> get copyWith => __$QdrantStatsCopyWithImpl<_QdrantStats>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$QdrantStatsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _QdrantStats&&(identical(other.status, status) || other.status == status)&&(identical(other.pointsCount, pointsCount) || other.pointsCount == pointsCount)&&(identical(other.segmentsCount, segmentsCount) || other.segmentsCount == segmentsCount)&&(identical(other.indexedVectorsCount, indexedVectorsCount) || other.indexedVectorsCount == indexedVectorsCount)&&const DeepCollectionEquality().equals(other._payloadSchema, _payloadSchema));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,status,pointsCount,segmentsCount,indexedVectorsCount,const DeepCollectionEquality().hash(_payloadSchema));

@override
String toString() {
  return 'QdrantStats(status: $status, pointsCount: $pointsCount, segmentsCount: $segmentsCount, indexedVectorsCount: $indexedVectorsCount, payloadSchema: $payloadSchema)';
}


}

/// @nodoc
abstract mixin class _$QdrantStatsCopyWith<$Res> implements $QdrantStatsCopyWith<$Res> {
  factory _$QdrantStatsCopyWith(_QdrantStats value, $Res Function(_QdrantStats) _then) = __$QdrantStatsCopyWithImpl;
@override @useResult
$Res call({
 String status,@JsonKey(name: 'points_count') int pointsCount,@JsonKey(name: 'segments_count') int segmentsCount,@JsonKey(name: 'indexed_vectors_count') int? indexedVectorsCount,@JsonKey(name: 'payload_schema') Map<String, dynamic>? payloadSchema
});




}
/// @nodoc
class __$QdrantStatsCopyWithImpl<$Res>
    implements _$QdrantStatsCopyWith<$Res> {
  __$QdrantStatsCopyWithImpl(this._self, this._then);

  final _QdrantStats _self;
  final $Res Function(_QdrantStats) _then;

/// Create a copy of QdrantStats
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? pointsCount = null,Object? segmentsCount = null,Object? indexedVectorsCount = freezed,Object? payloadSchema = freezed,}) {
  return _then(_QdrantStats(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,pointsCount: null == pointsCount ? _self.pointsCount : pointsCount // ignore: cast_nullable_to_non_nullable
as int,segmentsCount: null == segmentsCount ? _self.segmentsCount : segmentsCount // ignore: cast_nullable_to_non_nullable
as int,indexedVectorsCount: freezed == indexedVectorsCount ? _self.indexedVectorsCount : indexedVectorsCount // ignore: cast_nullable_to_non_nullable
as int?,payloadSchema: freezed == payloadSchema ? _self._payloadSchema : payloadSchema // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}


}


/// @nodoc
mixin _$ModelPerformance {

@JsonKey(name: 'model_name') String get modelName; String get node;@JsonKey(name: 'avg_tokens_per_sec') double get avgTokensPerSec;@JsonKey(name: 'avg_latency_ms') double get avgLatencyMs;@JsonKey(name: 'total_executions') int get totalExecutions;
/// Create a copy of ModelPerformance
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelPerformanceCopyWith<ModelPerformance> get copyWith => _$ModelPerformanceCopyWithImpl<ModelPerformance>(this as ModelPerformance, _$identity);

  /// Serializes this ModelPerformance to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelPerformance&&(identical(other.modelName, modelName) || other.modelName == modelName)&&(identical(other.node, node) || other.node == node)&&(identical(other.avgTokensPerSec, avgTokensPerSec) || other.avgTokensPerSec == avgTokensPerSec)&&(identical(other.avgLatencyMs, avgLatencyMs) || other.avgLatencyMs == avgLatencyMs)&&(identical(other.totalExecutions, totalExecutions) || other.totalExecutions == totalExecutions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,modelName,node,avgTokensPerSec,avgLatencyMs,totalExecutions);

@override
String toString() {
  return 'ModelPerformance(modelName: $modelName, node: $node, avgTokensPerSec: $avgTokensPerSec, avgLatencyMs: $avgLatencyMs, totalExecutions: $totalExecutions)';
}


}

/// @nodoc
abstract mixin class $ModelPerformanceCopyWith<$Res>  {
  factory $ModelPerformanceCopyWith(ModelPerformance value, $Res Function(ModelPerformance) _then) = _$ModelPerformanceCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'model_name') String modelName, String node,@JsonKey(name: 'avg_tokens_per_sec') double avgTokensPerSec,@JsonKey(name: 'avg_latency_ms') double avgLatencyMs,@JsonKey(name: 'total_executions') int totalExecutions
});




}
/// @nodoc
class _$ModelPerformanceCopyWithImpl<$Res>
    implements $ModelPerformanceCopyWith<$Res> {
  _$ModelPerformanceCopyWithImpl(this._self, this._then);

  final ModelPerformance _self;
  final $Res Function(ModelPerformance) _then;

/// Create a copy of ModelPerformance
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelName = null,Object? node = null,Object? avgTokensPerSec = null,Object? avgLatencyMs = null,Object? totalExecutions = null,}) {
  return _then(_self.copyWith(
modelName: null == modelName ? _self.modelName : modelName // ignore: cast_nullable_to_non_nullable
as String,node: null == node ? _self.node : node // ignore: cast_nullable_to_non_nullable
as String,avgTokensPerSec: null == avgTokensPerSec ? _self.avgTokensPerSec : avgTokensPerSec // ignore: cast_nullable_to_non_nullable
as double,avgLatencyMs: null == avgLatencyMs ? _self.avgLatencyMs : avgLatencyMs // ignore: cast_nullable_to_non_nullable
as double,totalExecutions: null == totalExecutions ? _self.totalExecutions : totalExecutions // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelPerformance].
extension ModelPerformancePatterns on ModelPerformance {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelPerformance value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelPerformance() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelPerformance value)  $default,){
final _that = this;
switch (_that) {
case _ModelPerformance():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelPerformance value)?  $default,){
final _that = this;
switch (_that) {
case _ModelPerformance() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'model_name')  String modelName,  String node, @JsonKey(name: 'avg_tokens_per_sec')  double avgTokensPerSec, @JsonKey(name: 'avg_latency_ms')  double avgLatencyMs, @JsonKey(name: 'total_executions')  int totalExecutions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelPerformance() when $default != null:
return $default(_that.modelName,_that.node,_that.avgTokensPerSec,_that.avgLatencyMs,_that.totalExecutions);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'model_name')  String modelName,  String node, @JsonKey(name: 'avg_tokens_per_sec')  double avgTokensPerSec, @JsonKey(name: 'avg_latency_ms')  double avgLatencyMs, @JsonKey(name: 'total_executions')  int totalExecutions)  $default,) {final _that = this;
switch (_that) {
case _ModelPerformance():
return $default(_that.modelName,_that.node,_that.avgTokensPerSec,_that.avgLatencyMs,_that.totalExecutions);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'model_name')  String modelName,  String node, @JsonKey(name: 'avg_tokens_per_sec')  double avgTokensPerSec, @JsonKey(name: 'avg_latency_ms')  double avgLatencyMs, @JsonKey(name: 'total_executions')  int totalExecutions)?  $default,) {final _that = this;
switch (_that) {
case _ModelPerformance() when $default != null:
return $default(_that.modelName,_that.node,_that.avgTokensPerSec,_that.avgLatencyMs,_that.totalExecutions);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ModelPerformance implements ModelPerformance {
  const _ModelPerformance({@JsonKey(name: 'model_name') required this.modelName, required this.node, @JsonKey(name: 'avg_tokens_per_sec') required this.avgTokensPerSec, @JsonKey(name: 'avg_latency_ms') required this.avgLatencyMs, @JsonKey(name: 'total_executions') required this.totalExecutions});
  factory _ModelPerformance.fromJson(Map<String, dynamic> json) => _$ModelPerformanceFromJson(json);

@override@JsonKey(name: 'model_name') final  String modelName;
@override final  String node;
@override@JsonKey(name: 'avg_tokens_per_sec') final  double avgTokensPerSec;
@override@JsonKey(name: 'avg_latency_ms') final  double avgLatencyMs;
@override@JsonKey(name: 'total_executions') final  int totalExecutions;

/// Create a copy of ModelPerformance
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelPerformanceCopyWith<_ModelPerformance> get copyWith => __$ModelPerformanceCopyWithImpl<_ModelPerformance>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ModelPerformanceToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelPerformance&&(identical(other.modelName, modelName) || other.modelName == modelName)&&(identical(other.node, node) || other.node == node)&&(identical(other.avgTokensPerSec, avgTokensPerSec) || other.avgTokensPerSec == avgTokensPerSec)&&(identical(other.avgLatencyMs, avgLatencyMs) || other.avgLatencyMs == avgLatencyMs)&&(identical(other.totalExecutions, totalExecutions) || other.totalExecutions == totalExecutions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,modelName,node,avgTokensPerSec,avgLatencyMs,totalExecutions);

@override
String toString() {
  return 'ModelPerformance(modelName: $modelName, node: $node, avgTokensPerSec: $avgTokensPerSec, avgLatencyMs: $avgLatencyMs, totalExecutions: $totalExecutions)';
}


}

/// @nodoc
abstract mixin class _$ModelPerformanceCopyWith<$Res> implements $ModelPerformanceCopyWith<$Res> {
  factory _$ModelPerformanceCopyWith(_ModelPerformance value, $Res Function(_ModelPerformance) _then) = __$ModelPerformanceCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'model_name') String modelName, String node,@JsonKey(name: 'avg_tokens_per_sec') double avgTokensPerSec,@JsonKey(name: 'avg_latency_ms') double avgLatencyMs,@JsonKey(name: 'total_executions') int totalExecutions
});




}
/// @nodoc
class __$ModelPerformanceCopyWithImpl<$Res>
    implements _$ModelPerformanceCopyWith<$Res> {
  __$ModelPerformanceCopyWithImpl(this._self, this._then);

  final _ModelPerformance _self;
  final $Res Function(_ModelPerformance) _then;

/// Create a copy of ModelPerformance
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modelName = null,Object? node = null,Object? avgTokensPerSec = null,Object? avgLatencyMs = null,Object? totalExecutions = null,}) {
  return _then(_ModelPerformance(
modelName: null == modelName ? _self.modelName : modelName // ignore: cast_nullable_to_non_nullable
as String,node: null == node ? _self.node : node // ignore: cast_nullable_to_non_nullable
as String,avgTokensPerSec: null == avgTokensPerSec ? _self.avgTokensPerSec : avgTokensPerSec // ignore: cast_nullable_to_non_nullable
as double,avgLatencyMs: null == avgLatencyMs ? _self.avgLatencyMs : avgLatencyMs // ignore: cast_nullable_to_non_nullable
as double,totalExecutions: null == totalExecutions ? _self.totalExecutions : totalExecutions // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$SessionHealth {

@JsonKey(name: 'session_id') int get sessionId;@JsonKey(name: 'total_requests') int get totalRequests;@JsonKey(name: 'successful_requests') int get successfulRequests;@JsonKey(name: 'success_rate') double get successRate;@JsonKey(name: 'avg_latency_ms') double? get avgLatencyMs;@JsonKey(name: 'total_tokens') int? get totalTokens;@JsonKey(name: 'prompt_count') int? get promptCount;@JsonKey(name: 'response_count') int? get responseCount;@JsonKey(name: 'memory_count') int? get memoryCount;@JsonKey(name: 'tag_count') int? get tagCount; String get status;
/// Create a copy of SessionHealth
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionHealthCopyWith<SessionHealth> get copyWith => _$SessionHealthCopyWithImpl<SessionHealth>(this as SessionHealth, _$identity);

  /// Serializes this SessionHealth to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionHealth&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.totalRequests, totalRequests) || other.totalRequests == totalRequests)&&(identical(other.successfulRequests, successfulRequests) || other.successfulRequests == successfulRequests)&&(identical(other.successRate, successRate) || other.successRate == successRate)&&(identical(other.avgLatencyMs, avgLatencyMs) || other.avgLatencyMs == avgLatencyMs)&&(identical(other.totalTokens, totalTokens) || other.totalTokens == totalTokens)&&(identical(other.promptCount, promptCount) || other.promptCount == promptCount)&&(identical(other.responseCount, responseCount) || other.responseCount == responseCount)&&(identical(other.memoryCount, memoryCount) || other.memoryCount == memoryCount)&&(identical(other.tagCount, tagCount) || other.tagCount == tagCount)&&(identical(other.status, status) || other.status == status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,sessionId,totalRequests,successfulRequests,successRate,avgLatencyMs,totalTokens,promptCount,responseCount,memoryCount,tagCount,status);

@override
String toString() {
  return 'SessionHealth(sessionId: $sessionId, totalRequests: $totalRequests, successfulRequests: $successfulRequests, successRate: $successRate, avgLatencyMs: $avgLatencyMs, totalTokens: $totalTokens, promptCount: $promptCount, responseCount: $responseCount, memoryCount: $memoryCount, tagCount: $tagCount, status: $status)';
}


}

/// @nodoc
abstract mixin class $SessionHealthCopyWith<$Res>  {
  factory $SessionHealthCopyWith(SessionHealth value, $Res Function(SessionHealth) _then) = _$SessionHealthCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'session_id') int sessionId,@JsonKey(name: 'total_requests') int totalRequests,@JsonKey(name: 'successful_requests') int successfulRequests,@JsonKey(name: 'success_rate') double successRate,@JsonKey(name: 'avg_latency_ms') double? avgLatencyMs,@JsonKey(name: 'total_tokens') int? totalTokens,@JsonKey(name: 'prompt_count') int? promptCount,@JsonKey(name: 'response_count') int? responseCount,@JsonKey(name: 'memory_count') int? memoryCount,@JsonKey(name: 'tag_count') int? tagCount, String status
});




}
/// @nodoc
class _$SessionHealthCopyWithImpl<$Res>
    implements $SessionHealthCopyWith<$Res> {
  _$SessionHealthCopyWithImpl(this._self, this._then);

  final SessionHealth _self;
  final $Res Function(SessionHealth) _then;

/// Create a copy of SessionHealth
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? totalRequests = null,Object? successfulRequests = null,Object? successRate = null,Object? avgLatencyMs = freezed,Object? totalTokens = freezed,Object? promptCount = freezed,Object? responseCount = freezed,Object? memoryCount = freezed,Object? tagCount = freezed,Object? status = null,}) {
  return _then(_self.copyWith(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as int,totalRequests: null == totalRequests ? _self.totalRequests : totalRequests // ignore: cast_nullable_to_non_nullable
as int,successfulRequests: null == successfulRequests ? _self.successfulRequests : successfulRequests // ignore: cast_nullable_to_non_nullable
as int,successRate: null == successRate ? _self.successRate : successRate // ignore: cast_nullable_to_non_nullable
as double,avgLatencyMs: freezed == avgLatencyMs ? _self.avgLatencyMs : avgLatencyMs // ignore: cast_nullable_to_non_nullable
as double?,totalTokens: freezed == totalTokens ? _self.totalTokens : totalTokens // ignore: cast_nullable_to_non_nullable
as int?,promptCount: freezed == promptCount ? _self.promptCount : promptCount // ignore: cast_nullable_to_non_nullable
as int?,responseCount: freezed == responseCount ? _self.responseCount : responseCount // ignore: cast_nullable_to_non_nullable
as int?,memoryCount: freezed == memoryCount ? _self.memoryCount : memoryCount // ignore: cast_nullable_to_non_nullable
as int?,tagCount: freezed == tagCount ? _self.tagCount : tagCount // ignore: cast_nullable_to_non_nullable
as int?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [SessionHealth].
extension SessionHealthPatterns on SessionHealth {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionHealth value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionHealth() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionHealth value)  $default,){
final _that = this;
switch (_that) {
case _SessionHealth():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionHealth value)?  $default,){
final _that = this;
switch (_that) {
case _SessionHealth() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'session_id')  int sessionId, @JsonKey(name: 'total_requests')  int totalRequests, @JsonKey(name: 'successful_requests')  int successfulRequests, @JsonKey(name: 'success_rate')  double successRate, @JsonKey(name: 'avg_latency_ms')  double? avgLatencyMs, @JsonKey(name: 'total_tokens')  int? totalTokens, @JsonKey(name: 'prompt_count')  int? promptCount, @JsonKey(name: 'response_count')  int? responseCount, @JsonKey(name: 'memory_count')  int? memoryCount, @JsonKey(name: 'tag_count')  int? tagCount,  String status)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionHealth() when $default != null:
return $default(_that.sessionId,_that.totalRequests,_that.successfulRequests,_that.successRate,_that.avgLatencyMs,_that.totalTokens,_that.promptCount,_that.responseCount,_that.memoryCount,_that.tagCount,_that.status);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'session_id')  int sessionId, @JsonKey(name: 'total_requests')  int totalRequests, @JsonKey(name: 'successful_requests')  int successfulRequests, @JsonKey(name: 'success_rate')  double successRate, @JsonKey(name: 'avg_latency_ms')  double? avgLatencyMs, @JsonKey(name: 'total_tokens')  int? totalTokens, @JsonKey(name: 'prompt_count')  int? promptCount, @JsonKey(name: 'response_count')  int? responseCount, @JsonKey(name: 'memory_count')  int? memoryCount, @JsonKey(name: 'tag_count')  int? tagCount,  String status)  $default,) {final _that = this;
switch (_that) {
case _SessionHealth():
return $default(_that.sessionId,_that.totalRequests,_that.successfulRequests,_that.successRate,_that.avgLatencyMs,_that.totalTokens,_that.promptCount,_that.responseCount,_that.memoryCount,_that.tagCount,_that.status);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'session_id')  int sessionId, @JsonKey(name: 'total_requests')  int totalRequests, @JsonKey(name: 'successful_requests')  int successfulRequests, @JsonKey(name: 'success_rate')  double successRate, @JsonKey(name: 'avg_latency_ms')  double? avgLatencyMs, @JsonKey(name: 'total_tokens')  int? totalTokens, @JsonKey(name: 'prompt_count')  int? promptCount, @JsonKey(name: 'response_count')  int? responseCount, @JsonKey(name: 'memory_count')  int? memoryCount, @JsonKey(name: 'tag_count')  int? tagCount,  String status)?  $default,) {final _that = this;
switch (_that) {
case _SessionHealth() when $default != null:
return $default(_that.sessionId,_that.totalRequests,_that.successfulRequests,_that.successRate,_that.avgLatencyMs,_that.totalTokens,_that.promptCount,_that.responseCount,_that.memoryCount,_that.tagCount,_that.status);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SessionHealth implements SessionHealth {
  const _SessionHealth({@JsonKey(name: 'session_id') required this.sessionId, @JsonKey(name: 'total_requests') required this.totalRequests, @JsonKey(name: 'successful_requests') required this.successfulRequests, @JsonKey(name: 'success_rate') required this.successRate, @JsonKey(name: 'avg_latency_ms') this.avgLatencyMs, @JsonKey(name: 'total_tokens') this.totalTokens, @JsonKey(name: 'prompt_count') this.promptCount, @JsonKey(name: 'response_count') this.responseCount, @JsonKey(name: 'memory_count') this.memoryCount, @JsonKey(name: 'tag_count') this.tagCount, required this.status});
  factory _SessionHealth.fromJson(Map<String, dynamic> json) => _$SessionHealthFromJson(json);

@override@JsonKey(name: 'session_id') final  int sessionId;
@override@JsonKey(name: 'total_requests') final  int totalRequests;
@override@JsonKey(name: 'successful_requests') final  int successfulRequests;
@override@JsonKey(name: 'success_rate') final  double successRate;
@override@JsonKey(name: 'avg_latency_ms') final  double? avgLatencyMs;
@override@JsonKey(name: 'total_tokens') final  int? totalTokens;
@override@JsonKey(name: 'prompt_count') final  int? promptCount;
@override@JsonKey(name: 'response_count') final  int? responseCount;
@override@JsonKey(name: 'memory_count') final  int? memoryCount;
@override@JsonKey(name: 'tag_count') final  int? tagCount;
@override final  String status;

/// Create a copy of SessionHealth
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionHealthCopyWith<_SessionHealth> get copyWith => __$SessionHealthCopyWithImpl<_SessionHealth>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SessionHealthToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionHealth&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.totalRequests, totalRequests) || other.totalRequests == totalRequests)&&(identical(other.successfulRequests, successfulRequests) || other.successfulRequests == successfulRequests)&&(identical(other.successRate, successRate) || other.successRate == successRate)&&(identical(other.avgLatencyMs, avgLatencyMs) || other.avgLatencyMs == avgLatencyMs)&&(identical(other.totalTokens, totalTokens) || other.totalTokens == totalTokens)&&(identical(other.promptCount, promptCount) || other.promptCount == promptCount)&&(identical(other.responseCount, responseCount) || other.responseCount == responseCount)&&(identical(other.memoryCount, memoryCount) || other.memoryCount == memoryCount)&&(identical(other.tagCount, tagCount) || other.tagCount == tagCount)&&(identical(other.status, status) || other.status == status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,sessionId,totalRequests,successfulRequests,successRate,avgLatencyMs,totalTokens,promptCount,responseCount,memoryCount,tagCount,status);

@override
String toString() {
  return 'SessionHealth(sessionId: $sessionId, totalRequests: $totalRequests, successfulRequests: $successfulRequests, successRate: $successRate, avgLatencyMs: $avgLatencyMs, totalTokens: $totalTokens, promptCount: $promptCount, responseCount: $responseCount, memoryCount: $memoryCount, tagCount: $tagCount, status: $status)';
}


}

/// @nodoc
abstract mixin class _$SessionHealthCopyWith<$Res> implements $SessionHealthCopyWith<$Res> {
  factory _$SessionHealthCopyWith(_SessionHealth value, $Res Function(_SessionHealth) _then) = __$SessionHealthCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'session_id') int sessionId,@JsonKey(name: 'total_requests') int totalRequests,@JsonKey(name: 'successful_requests') int successfulRequests,@JsonKey(name: 'success_rate') double successRate,@JsonKey(name: 'avg_latency_ms') double? avgLatencyMs,@JsonKey(name: 'total_tokens') int? totalTokens,@JsonKey(name: 'prompt_count') int? promptCount,@JsonKey(name: 'response_count') int? responseCount,@JsonKey(name: 'memory_count') int? memoryCount,@JsonKey(name: 'tag_count') int? tagCount, String status
});




}
/// @nodoc
class __$SessionHealthCopyWithImpl<$Res>
    implements _$SessionHealthCopyWith<$Res> {
  __$SessionHealthCopyWithImpl(this._self, this._then);

  final _SessionHealth _self;
  final $Res Function(_SessionHealth) _then;

/// Create a copy of SessionHealth
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? totalRequests = null,Object? successfulRequests = null,Object? successRate = null,Object? avgLatencyMs = freezed,Object? totalTokens = freezed,Object? promptCount = freezed,Object? responseCount = freezed,Object? memoryCount = freezed,Object? tagCount = freezed,Object? status = null,}) {
  return _then(_SessionHealth(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as int,totalRequests: null == totalRequests ? _self.totalRequests : totalRequests // ignore: cast_nullable_to_non_nullable
as int,successfulRequests: null == successfulRequests ? _self.successfulRequests : successfulRequests // ignore: cast_nullable_to_non_nullable
as int,successRate: null == successRate ? _self.successRate : successRate // ignore: cast_nullable_to_non_nullable
as double,avgLatencyMs: freezed == avgLatencyMs ? _self.avgLatencyMs : avgLatencyMs // ignore: cast_nullable_to_non_nullable
as double?,totalTokens: freezed == totalTokens ? _self.totalTokens : totalTokens // ignore: cast_nullable_to_non_nullable
as int?,promptCount: freezed == promptCount ? _self.promptCount : promptCount // ignore: cast_nullable_to_non_nullable
as int?,responseCount: freezed == responseCount ? _self.responseCount : responseCount // ignore: cast_nullable_to_non_nullable
as int?,memoryCount: freezed == memoryCount ? _self.memoryCount : memoryCount // ignore: cast_nullable_to_non_nullable
as int?,tagCount: freezed == tagCount ? _self.tagCount : tagCount // ignore: cast_nullable_to_non_nullable
as int?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$CodeVector {

 int get id;@JsonKey(name: 'ingestion_id') int? get ingestionId; Map<String, dynamic>? get metadata;@JsonKey(name: 'created_at') DateTime get createdAt; List<String> get tags;
/// Create a copy of CodeVector
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CodeVectorCopyWith<CodeVector> get copyWith => _$CodeVectorCopyWithImpl<CodeVector>(this as CodeVector, _$identity);

  /// Serializes this CodeVector to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CodeVector&&(identical(other.id, id) || other.id == id)&&(identical(other.ingestionId, ingestionId) || other.ingestionId == ingestionId)&&const DeepCollectionEquality().equals(other.metadata, metadata)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&const DeepCollectionEquality().equals(other.tags, tags));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,ingestionId,const DeepCollectionEquality().hash(metadata),createdAt,const DeepCollectionEquality().hash(tags));

@override
String toString() {
  return 'CodeVector(id: $id, ingestionId: $ingestionId, metadata: $metadata, createdAt: $createdAt, tags: $tags)';
}


}

/// @nodoc
abstract mixin class $CodeVectorCopyWith<$Res>  {
  factory $CodeVectorCopyWith(CodeVector value, $Res Function(CodeVector) _then) = _$CodeVectorCopyWithImpl;
@useResult
$Res call({
 int id,@JsonKey(name: 'ingestion_id') int? ingestionId, Map<String, dynamic>? metadata,@JsonKey(name: 'created_at') DateTime createdAt, List<String> tags
});




}
/// @nodoc
class _$CodeVectorCopyWithImpl<$Res>
    implements $CodeVectorCopyWith<$Res> {
  _$CodeVectorCopyWithImpl(this._self, this._then);

  final CodeVector _self;
  final $Res Function(CodeVector) _then;

/// Create a copy of CodeVector
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? ingestionId = freezed,Object? metadata = freezed,Object? createdAt = null,Object? tags = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,ingestionId: freezed == ingestionId ? _self.ingestionId : ingestionId // ignore: cast_nullable_to_non_nullable
as int?,metadata: freezed == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [CodeVector].
extension CodeVectorPatterns on CodeVector {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CodeVector value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CodeVector() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CodeVector value)  $default,){
final _that = this;
switch (_that) {
case _CodeVector():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CodeVector value)?  $default,){
final _that = this;
switch (_that) {
case _CodeVector() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'ingestion_id')  int? ingestionId,  Map<String, dynamic>? metadata, @JsonKey(name: 'created_at')  DateTime createdAt,  List<String> tags)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CodeVector() when $default != null:
return $default(_that.id,_that.ingestionId,_that.metadata,_that.createdAt,_that.tags);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id, @JsonKey(name: 'ingestion_id')  int? ingestionId,  Map<String, dynamic>? metadata, @JsonKey(name: 'created_at')  DateTime createdAt,  List<String> tags)  $default,) {final _that = this;
switch (_that) {
case _CodeVector():
return $default(_that.id,_that.ingestionId,_that.metadata,_that.createdAt,_that.tags);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id, @JsonKey(name: 'ingestion_id')  int? ingestionId,  Map<String, dynamic>? metadata, @JsonKey(name: 'created_at')  DateTime createdAt,  List<String> tags)?  $default,) {final _that = this;
switch (_that) {
case _CodeVector() when $default != null:
return $default(_that.id,_that.ingestionId,_that.metadata,_that.createdAt,_that.tags);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CodeVector implements CodeVector {
  const _CodeVector({required this.id, @JsonKey(name: 'ingestion_id') this.ingestionId, final  Map<String, dynamic>? metadata, @JsonKey(name: 'created_at') required this.createdAt, required final  List<String> tags}): _metadata = metadata,_tags = tags;
  factory _CodeVector.fromJson(Map<String, dynamic> json) => _$CodeVectorFromJson(json);

@override final  int id;
@override@JsonKey(name: 'ingestion_id') final  int? ingestionId;
 final  Map<String, dynamic>? _metadata;
@override Map<String, dynamic>? get metadata {
  final value = _metadata;
  if (value == null) return null;
  if (_metadata is EqualUnmodifiableMapView) return _metadata;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

@override@JsonKey(name: 'created_at') final  DateTime createdAt;
 final  List<String> _tags;
@override List<String> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}


/// Create a copy of CodeVector
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CodeVectorCopyWith<_CodeVector> get copyWith => __$CodeVectorCopyWithImpl<_CodeVector>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CodeVectorToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CodeVector&&(identical(other.id, id) || other.id == id)&&(identical(other.ingestionId, ingestionId) || other.ingestionId == ingestionId)&&const DeepCollectionEquality().equals(other._metadata, _metadata)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&const DeepCollectionEquality().equals(other._tags, _tags));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,ingestionId,const DeepCollectionEquality().hash(_metadata),createdAt,const DeepCollectionEquality().hash(_tags));

@override
String toString() {
  return 'CodeVector(id: $id, ingestionId: $ingestionId, metadata: $metadata, createdAt: $createdAt, tags: $tags)';
}


}

/// @nodoc
abstract mixin class _$CodeVectorCopyWith<$Res> implements $CodeVectorCopyWith<$Res> {
  factory _$CodeVectorCopyWith(_CodeVector value, $Res Function(_CodeVector) _then) = __$CodeVectorCopyWithImpl;
@override @useResult
$Res call({
 int id,@JsonKey(name: 'ingestion_id') int? ingestionId, Map<String, dynamic>? metadata,@JsonKey(name: 'created_at') DateTime createdAt, List<String> tags
});




}
/// @nodoc
class __$CodeVectorCopyWithImpl<$Res>
    implements _$CodeVectorCopyWith<$Res> {
  __$CodeVectorCopyWithImpl(this._self, this._then);

  final _CodeVector _self;
  final $Res Function(_CodeVector) _then;

/// Create a copy of CodeVector
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? ingestionId = freezed,Object? metadata = freezed,Object? createdAt = null,Object? tags = null,}) {
  return _then(_CodeVector(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,ingestionId: freezed == ingestionId ? _self.ingestionId : ingestionId // ignore: cast_nullable_to_non_nullable
as int?,metadata: freezed == metadata ? _self._metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}


/// @nodoc
mixin _$VirtualFile {

 String get path; String get bucket;@JsonKey(name: 'created_at') DateTime get createdAt; List<String> get tags; String get status;
/// Create a copy of VirtualFile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VirtualFileCopyWith<VirtualFile> get copyWith => _$VirtualFileCopyWithImpl<VirtualFile>(this as VirtualFile, _$identity);

  /// Serializes this VirtualFile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VirtualFile&&(identical(other.path, path) || other.path == path)&&(identical(other.bucket, bucket) || other.bucket == bucket)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&const DeepCollectionEquality().equals(other.tags, tags)&&(identical(other.status, status) || other.status == status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,path,bucket,createdAt,const DeepCollectionEquality().hash(tags),status);

@override
String toString() {
  return 'VirtualFile(path: $path, bucket: $bucket, createdAt: $createdAt, tags: $tags, status: $status)';
}


}

/// @nodoc
abstract mixin class $VirtualFileCopyWith<$Res>  {
  factory $VirtualFileCopyWith(VirtualFile value, $Res Function(VirtualFile) _then) = _$VirtualFileCopyWithImpl;
@useResult
$Res call({
 String path, String bucket,@JsonKey(name: 'created_at') DateTime createdAt, List<String> tags, String status
});




}
/// @nodoc
class _$VirtualFileCopyWithImpl<$Res>
    implements $VirtualFileCopyWith<$Res> {
  _$VirtualFileCopyWithImpl(this._self, this._then);

  final VirtualFile _self;
  final $Res Function(VirtualFile) _then;

/// Create a copy of VirtualFile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,Object? bucket = null,Object? createdAt = null,Object? tags = null,Object? status = null,}) {
  return _then(_self.copyWith(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,bucket: null == bucket ? _self.bucket : bucket // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [VirtualFile].
extension VirtualFilePatterns on VirtualFile {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VirtualFile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VirtualFile() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VirtualFile value)  $default,){
final _that = this;
switch (_that) {
case _VirtualFile():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VirtualFile value)?  $default,){
final _that = this;
switch (_that) {
case _VirtualFile() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String path,  String bucket, @JsonKey(name: 'created_at')  DateTime createdAt,  List<String> tags,  String status)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VirtualFile() when $default != null:
return $default(_that.path,_that.bucket,_that.createdAt,_that.tags,_that.status);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String path,  String bucket, @JsonKey(name: 'created_at')  DateTime createdAt,  List<String> tags,  String status)  $default,) {final _that = this;
switch (_that) {
case _VirtualFile():
return $default(_that.path,_that.bucket,_that.createdAt,_that.tags,_that.status);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String path,  String bucket, @JsonKey(name: 'created_at')  DateTime createdAt,  List<String> tags,  String status)?  $default,) {final _that = this;
switch (_that) {
case _VirtualFile() when $default != null:
return $default(_that.path,_that.bucket,_that.createdAt,_that.tags,_that.status);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _VirtualFile implements VirtualFile {
  const _VirtualFile({required this.path, required this.bucket, @JsonKey(name: 'created_at') required this.createdAt, required final  List<String> tags, required this.status}): _tags = tags;
  factory _VirtualFile.fromJson(Map<String, dynamic> json) => _$VirtualFileFromJson(json);

@override final  String path;
@override final  String bucket;
@override@JsonKey(name: 'created_at') final  DateTime createdAt;
 final  List<String> _tags;
@override List<String> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}

@override final  String status;

/// Create a copy of VirtualFile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VirtualFileCopyWith<_VirtualFile> get copyWith => __$VirtualFileCopyWithImpl<_VirtualFile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$VirtualFileToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _VirtualFile&&(identical(other.path, path) || other.path == path)&&(identical(other.bucket, bucket) || other.bucket == bucket)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&const DeepCollectionEquality().equals(other._tags, _tags)&&(identical(other.status, status) || other.status == status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,path,bucket,createdAt,const DeepCollectionEquality().hash(_tags),status);

@override
String toString() {
  return 'VirtualFile(path: $path, bucket: $bucket, createdAt: $createdAt, tags: $tags, status: $status)';
}


}

/// @nodoc
abstract mixin class _$VirtualFileCopyWith<$Res> implements $VirtualFileCopyWith<$Res> {
  factory _$VirtualFileCopyWith(_VirtualFile value, $Res Function(_VirtualFile) _then) = __$VirtualFileCopyWithImpl;
@override @useResult
$Res call({
 String path, String bucket,@JsonKey(name: 'created_at') DateTime createdAt, List<String> tags, String status
});




}
/// @nodoc
class __$VirtualFileCopyWithImpl<$Res>
    implements _$VirtualFileCopyWith<$Res> {
  __$VirtualFileCopyWithImpl(this._self, this._then);

  final _VirtualFile _self;
  final $Res Function(_VirtualFile) _then;

/// Create a copy of VirtualFile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? bucket = null,Object? createdAt = null,Object? tags = null,Object? status = null,}) {
  return _then(_VirtualFile(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,bucket: null == bucket ? _self.bucket : bucket // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$AuditEntry {

 String get type;// RETRIEVAL, MEMORY
 String get detail;@JsonKey(name: 'created_at') DateTime get createdAt;
/// Create a copy of AuditEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AuditEntryCopyWith<AuditEntry> get copyWith => _$AuditEntryCopyWithImpl<AuditEntry>(this as AuditEntry, _$identity);

  /// Serializes this AuditEntry to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuditEntry&&(identical(other.type, type) || other.type == type)&&(identical(other.detail, detail) || other.detail == detail)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,detail,createdAt);

@override
String toString() {
  return 'AuditEntry(type: $type, detail: $detail, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $AuditEntryCopyWith<$Res>  {
  factory $AuditEntryCopyWith(AuditEntry value, $Res Function(AuditEntry) _then) = _$AuditEntryCopyWithImpl;
@useResult
$Res call({
 String type, String detail,@JsonKey(name: 'created_at') DateTime createdAt
});




}
/// @nodoc
class _$AuditEntryCopyWithImpl<$Res>
    implements $AuditEntryCopyWith<$Res> {
  _$AuditEntryCopyWithImpl(this._self, this._then);

  final AuditEntry _self;
  final $Res Function(AuditEntry) _then;

/// Create a copy of AuditEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? detail = null,Object? createdAt = null,}) {
  return _then(_self.copyWith(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [AuditEntry].
extension AuditEntryPatterns on AuditEntry {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AuditEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AuditEntry() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AuditEntry value)  $default,){
final _that = this;
switch (_that) {
case _AuditEntry():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AuditEntry value)?  $default,){
final _that = this;
switch (_that) {
case _AuditEntry() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String type,  String detail, @JsonKey(name: 'created_at')  DateTime createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AuditEntry() when $default != null:
return $default(_that.type,_that.detail,_that.createdAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String type,  String detail, @JsonKey(name: 'created_at')  DateTime createdAt)  $default,) {final _that = this;
switch (_that) {
case _AuditEntry():
return $default(_that.type,_that.detail,_that.createdAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String type,  String detail, @JsonKey(name: 'created_at')  DateTime createdAt)?  $default,) {final _that = this;
switch (_that) {
case _AuditEntry() when $default != null:
return $default(_that.type,_that.detail,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AuditEntry implements AuditEntry {
  const _AuditEntry({required this.type, required this.detail, @JsonKey(name: 'created_at') required this.createdAt});
  factory _AuditEntry.fromJson(Map<String, dynamic> json) => _$AuditEntryFromJson(json);

@override final  String type;
// RETRIEVAL, MEMORY
@override final  String detail;
@override@JsonKey(name: 'created_at') final  DateTime createdAt;

/// Create a copy of AuditEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AuditEntryCopyWith<_AuditEntry> get copyWith => __$AuditEntryCopyWithImpl<_AuditEntry>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AuditEntryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AuditEntry&&(identical(other.type, type) || other.type == type)&&(identical(other.detail, detail) || other.detail == detail)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,detail,createdAt);

@override
String toString() {
  return 'AuditEntry(type: $type, detail: $detail, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$AuditEntryCopyWith<$Res> implements $AuditEntryCopyWith<$Res> {
  factory _$AuditEntryCopyWith(_AuditEntry value, $Res Function(_AuditEntry) _then) = __$AuditEntryCopyWithImpl;
@override @useResult
$Res call({
 String type, String detail,@JsonKey(name: 'created_at') DateTime createdAt
});




}
/// @nodoc
class __$AuditEntryCopyWithImpl<$Res>
    implements _$AuditEntryCopyWith<$Res> {
  __$AuditEntryCopyWithImpl(this._self, this._then);

  final _AuditEntry _self;
  final $Res Function(_AuditEntry) _then;

/// Create a copy of AuditEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? detail = null,Object? createdAt = null,}) {
  return _then(_AuditEntry(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
