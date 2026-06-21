// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AppConfig {

 String get ragAdminApiUrl; bool get skipTlsVerification; String? get caCertPath; String get defaultBucketName; bool get darkMode; List<String> get availableModels; List<String> get availableEmbeddingModels; bool get memoryExplorerEnabled; bool get modelComparisonEnabled; int get promptTimeoutSeconds; int get connectTimeoutSeconds; int get receiveTimeoutSeconds;
/// Create a copy of AppConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppConfigCopyWith<AppConfig> get copyWith => _$AppConfigCopyWithImpl<AppConfig>(this as AppConfig, _$identity);

  /// Serializes this AppConfig to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppConfig&&(identical(other.ragAdminApiUrl, ragAdminApiUrl) || other.ragAdminApiUrl == ragAdminApiUrl)&&(identical(other.skipTlsVerification, skipTlsVerification) || other.skipTlsVerification == skipTlsVerification)&&(identical(other.caCertPath, caCertPath) || other.caCertPath == caCertPath)&&(identical(other.defaultBucketName, defaultBucketName) || other.defaultBucketName == defaultBucketName)&&(identical(other.darkMode, darkMode) || other.darkMode == darkMode)&&const DeepCollectionEquality().equals(other.availableModels, availableModels)&&const DeepCollectionEquality().equals(other.availableEmbeddingModels, availableEmbeddingModels)&&(identical(other.memoryExplorerEnabled, memoryExplorerEnabled) || other.memoryExplorerEnabled == memoryExplorerEnabled)&&(identical(other.modelComparisonEnabled, modelComparisonEnabled) || other.modelComparisonEnabled == modelComparisonEnabled)&&(identical(other.promptTimeoutSeconds, promptTimeoutSeconds) || other.promptTimeoutSeconds == promptTimeoutSeconds)&&(identical(other.connectTimeoutSeconds, connectTimeoutSeconds) || other.connectTimeoutSeconds == connectTimeoutSeconds)&&(identical(other.receiveTimeoutSeconds, receiveTimeoutSeconds) || other.receiveTimeoutSeconds == receiveTimeoutSeconds));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,ragAdminApiUrl,skipTlsVerification,caCertPath,defaultBucketName,darkMode,const DeepCollectionEquality().hash(availableModels),const DeepCollectionEquality().hash(availableEmbeddingModels),memoryExplorerEnabled,modelComparisonEnabled,promptTimeoutSeconds,connectTimeoutSeconds,receiveTimeoutSeconds);

@override
String toString() {
  return 'AppConfig(ragAdminApiUrl: $ragAdminApiUrl, skipTlsVerification: $skipTlsVerification, caCertPath: $caCertPath, defaultBucketName: $defaultBucketName, darkMode: $darkMode, availableModels: $availableModels, availableEmbeddingModels: $availableEmbeddingModels, memoryExplorerEnabled: $memoryExplorerEnabled, modelComparisonEnabled: $modelComparisonEnabled, promptTimeoutSeconds: $promptTimeoutSeconds, connectTimeoutSeconds: $connectTimeoutSeconds, receiveTimeoutSeconds: $receiveTimeoutSeconds)';
}


}

/// @nodoc
abstract mixin class $AppConfigCopyWith<$Res>  {
  factory $AppConfigCopyWith(AppConfig value, $Res Function(AppConfig) _then) = _$AppConfigCopyWithImpl;
@useResult
$Res call({
 String ragAdminApiUrl, bool skipTlsVerification, String? caCertPath, String defaultBucketName, bool darkMode, List<String> availableModels, List<String> availableEmbeddingModels, bool memoryExplorerEnabled, bool modelComparisonEnabled, int promptTimeoutSeconds, int connectTimeoutSeconds, int receiveTimeoutSeconds
});




}
/// @nodoc
class _$AppConfigCopyWithImpl<$Res>
    implements $AppConfigCopyWith<$Res> {
  _$AppConfigCopyWithImpl(this._self, this._then);

  final AppConfig _self;
  final $Res Function(AppConfig) _then;

/// Create a copy of AppConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? ragAdminApiUrl = null,Object? skipTlsVerification = null,Object? caCertPath = freezed,Object? defaultBucketName = null,Object? darkMode = null,Object? availableModels = null,Object? availableEmbeddingModels = null,Object? memoryExplorerEnabled = null,Object? modelComparisonEnabled = null,Object? promptTimeoutSeconds = null,Object? connectTimeoutSeconds = null,Object? receiveTimeoutSeconds = null,}) {
  return _then(_self.copyWith(
ragAdminApiUrl: null == ragAdminApiUrl ? _self.ragAdminApiUrl : ragAdminApiUrl // ignore: cast_nullable_to_non_nullable
as String,skipTlsVerification: null == skipTlsVerification ? _self.skipTlsVerification : skipTlsVerification // ignore: cast_nullable_to_non_nullable
as bool,caCertPath: freezed == caCertPath ? _self.caCertPath : caCertPath // ignore: cast_nullable_to_non_nullable
as String?,defaultBucketName: null == defaultBucketName ? _self.defaultBucketName : defaultBucketName // ignore: cast_nullable_to_non_nullable
as String,darkMode: null == darkMode ? _self.darkMode : darkMode // ignore: cast_nullable_to_non_nullable
as bool,availableModels: null == availableModels ? _self.availableModels : availableModels // ignore: cast_nullable_to_non_nullable
as List<String>,availableEmbeddingModels: null == availableEmbeddingModels ? _self.availableEmbeddingModels : availableEmbeddingModels // ignore: cast_nullable_to_non_nullable
as List<String>,memoryExplorerEnabled: null == memoryExplorerEnabled ? _self.memoryExplorerEnabled : memoryExplorerEnabled // ignore: cast_nullable_to_non_nullable
as bool,modelComparisonEnabled: null == modelComparisonEnabled ? _self.modelComparisonEnabled : modelComparisonEnabled // ignore: cast_nullable_to_non_nullable
as bool,promptTimeoutSeconds: null == promptTimeoutSeconds ? _self.promptTimeoutSeconds : promptTimeoutSeconds // ignore: cast_nullable_to_non_nullable
as int,connectTimeoutSeconds: null == connectTimeoutSeconds ? _self.connectTimeoutSeconds : connectTimeoutSeconds // ignore: cast_nullable_to_non_nullable
as int,receiveTimeoutSeconds: null == receiveTimeoutSeconds ? _self.receiveTimeoutSeconds : receiveTimeoutSeconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [AppConfig].
extension AppConfigPatterns on AppConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AppConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AppConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AppConfig value)  $default,){
final _that = this;
switch (_that) {
case _AppConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AppConfig value)?  $default,){
final _that = this;
switch (_that) {
case _AppConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String ragAdminApiUrl,  bool skipTlsVerification,  String? caCertPath,  String defaultBucketName,  bool darkMode,  List<String> availableModels,  List<String> availableEmbeddingModels,  bool memoryExplorerEnabled,  bool modelComparisonEnabled,  int promptTimeoutSeconds,  int connectTimeoutSeconds,  int receiveTimeoutSeconds)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppConfig() when $default != null:
return $default(_that.ragAdminApiUrl,_that.skipTlsVerification,_that.caCertPath,_that.defaultBucketName,_that.darkMode,_that.availableModels,_that.availableEmbeddingModels,_that.memoryExplorerEnabled,_that.modelComparisonEnabled,_that.promptTimeoutSeconds,_that.connectTimeoutSeconds,_that.receiveTimeoutSeconds);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String ragAdminApiUrl,  bool skipTlsVerification,  String? caCertPath,  String defaultBucketName,  bool darkMode,  List<String> availableModels,  List<String> availableEmbeddingModels,  bool memoryExplorerEnabled,  bool modelComparisonEnabled,  int promptTimeoutSeconds,  int connectTimeoutSeconds,  int receiveTimeoutSeconds)  $default,) {final _that = this;
switch (_that) {
case _AppConfig():
return $default(_that.ragAdminApiUrl,_that.skipTlsVerification,_that.caCertPath,_that.defaultBucketName,_that.darkMode,_that.availableModels,_that.availableEmbeddingModels,_that.memoryExplorerEnabled,_that.modelComparisonEnabled,_that.promptTimeoutSeconds,_that.connectTimeoutSeconds,_that.receiveTimeoutSeconds);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String ragAdminApiUrl,  bool skipTlsVerification,  String? caCertPath,  String defaultBucketName,  bool darkMode,  List<String> availableModels,  List<String> availableEmbeddingModels,  bool memoryExplorerEnabled,  bool modelComparisonEnabled,  int promptTimeoutSeconds,  int connectTimeoutSeconds,  int receiveTimeoutSeconds)?  $default,) {final _that = this;
switch (_that) {
case _AppConfig() when $default != null:
return $default(_that.ragAdminApiUrl,_that.skipTlsVerification,_that.caCertPath,_that.defaultBucketName,_that.darkMode,_that.availableModels,_that.availableEmbeddingModels,_that.memoryExplorerEnabled,_that.modelComparisonEnabled,_that.promptTimeoutSeconds,_that.connectTimeoutSeconds,_that.receiveTimeoutSeconds);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AppConfig extends AppConfig {
  const _AppConfig({this.ragAdminApiUrl = 'https://rag-admin-api.rag.hierocracy.home', this.skipTlsVerification = true, this.caCertPath, this.defaultBucketName = 'rag-codebase-bucket', this.darkMode = true, final  List<String> availableModels = const ['granite3.1-dense:8b', 'qwen3:32b', 'qwen2.5:32b', 'llama3.2:3b', 'llama3.1'], final  List<String> availableEmbeddingModels = const ['all-minilm:l6-v2', 'mxbai-embed-large', 'nomic-embed-text'], this.memoryExplorerEnabled = true, this.modelComparisonEnabled = true, this.promptTimeoutSeconds = 120, this.connectTimeoutSeconds = 10, this.receiveTimeoutSeconds = 30}): _availableModels = availableModels,_availableEmbeddingModels = availableEmbeddingModels,super._();
  factory _AppConfig.fromJson(Map<String, dynamic> json) => _$AppConfigFromJson(json);

@override@JsonKey() final  String ragAdminApiUrl;
@override@JsonKey() final  bool skipTlsVerification;
@override final  String? caCertPath;
@override@JsonKey() final  String defaultBucketName;
@override@JsonKey() final  bool darkMode;
 final  List<String> _availableModels;
@override@JsonKey() List<String> get availableModels {
  if (_availableModels is EqualUnmodifiableListView) return _availableModels;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_availableModels);
}

 final  List<String> _availableEmbeddingModels;
@override@JsonKey() List<String> get availableEmbeddingModels {
  if (_availableEmbeddingModels is EqualUnmodifiableListView) return _availableEmbeddingModels;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_availableEmbeddingModels);
}

@override@JsonKey() final  bool memoryExplorerEnabled;
@override@JsonKey() final  bool modelComparisonEnabled;
@override@JsonKey() final  int promptTimeoutSeconds;
@override@JsonKey() final  int connectTimeoutSeconds;
@override@JsonKey() final  int receiveTimeoutSeconds;

/// Create a copy of AppConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AppConfigCopyWith<_AppConfig> get copyWith => __$AppConfigCopyWithImpl<_AppConfig>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AppConfigToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppConfig&&(identical(other.ragAdminApiUrl, ragAdminApiUrl) || other.ragAdminApiUrl == ragAdminApiUrl)&&(identical(other.skipTlsVerification, skipTlsVerification) || other.skipTlsVerification == skipTlsVerification)&&(identical(other.caCertPath, caCertPath) || other.caCertPath == caCertPath)&&(identical(other.defaultBucketName, defaultBucketName) || other.defaultBucketName == defaultBucketName)&&(identical(other.darkMode, darkMode) || other.darkMode == darkMode)&&const DeepCollectionEquality().equals(other._availableModels, _availableModels)&&const DeepCollectionEquality().equals(other._availableEmbeddingModels, _availableEmbeddingModels)&&(identical(other.memoryExplorerEnabled, memoryExplorerEnabled) || other.memoryExplorerEnabled == memoryExplorerEnabled)&&(identical(other.modelComparisonEnabled, modelComparisonEnabled) || other.modelComparisonEnabled == modelComparisonEnabled)&&(identical(other.promptTimeoutSeconds, promptTimeoutSeconds) || other.promptTimeoutSeconds == promptTimeoutSeconds)&&(identical(other.connectTimeoutSeconds, connectTimeoutSeconds) || other.connectTimeoutSeconds == connectTimeoutSeconds)&&(identical(other.receiveTimeoutSeconds, receiveTimeoutSeconds) || other.receiveTimeoutSeconds == receiveTimeoutSeconds));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,ragAdminApiUrl,skipTlsVerification,caCertPath,defaultBucketName,darkMode,const DeepCollectionEquality().hash(_availableModels),const DeepCollectionEquality().hash(_availableEmbeddingModels),memoryExplorerEnabled,modelComparisonEnabled,promptTimeoutSeconds,connectTimeoutSeconds,receiveTimeoutSeconds);

@override
String toString() {
  return 'AppConfig(ragAdminApiUrl: $ragAdminApiUrl, skipTlsVerification: $skipTlsVerification, caCertPath: $caCertPath, defaultBucketName: $defaultBucketName, darkMode: $darkMode, availableModels: $availableModels, availableEmbeddingModels: $availableEmbeddingModels, memoryExplorerEnabled: $memoryExplorerEnabled, modelComparisonEnabled: $modelComparisonEnabled, promptTimeoutSeconds: $promptTimeoutSeconds, connectTimeoutSeconds: $connectTimeoutSeconds, receiveTimeoutSeconds: $receiveTimeoutSeconds)';
}


}

/// @nodoc
abstract mixin class _$AppConfigCopyWith<$Res> implements $AppConfigCopyWith<$Res> {
  factory _$AppConfigCopyWith(_AppConfig value, $Res Function(_AppConfig) _then) = __$AppConfigCopyWithImpl;
@override @useResult
$Res call({
 String ragAdminApiUrl, bool skipTlsVerification, String? caCertPath, String defaultBucketName, bool darkMode, List<String> availableModels, List<String> availableEmbeddingModels, bool memoryExplorerEnabled, bool modelComparisonEnabled, int promptTimeoutSeconds, int connectTimeoutSeconds, int receiveTimeoutSeconds
});




}
/// @nodoc
class __$AppConfigCopyWithImpl<$Res>
    implements _$AppConfigCopyWith<$Res> {
  __$AppConfigCopyWithImpl(this._self, this._then);

  final _AppConfig _self;
  final $Res Function(_AppConfig) _then;

/// Create a copy of AppConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? ragAdminApiUrl = null,Object? skipTlsVerification = null,Object? caCertPath = freezed,Object? defaultBucketName = null,Object? darkMode = null,Object? availableModels = null,Object? availableEmbeddingModels = null,Object? memoryExplorerEnabled = null,Object? modelComparisonEnabled = null,Object? promptTimeoutSeconds = null,Object? connectTimeoutSeconds = null,Object? receiveTimeoutSeconds = null,}) {
  return _then(_AppConfig(
ragAdminApiUrl: null == ragAdminApiUrl ? _self.ragAdminApiUrl : ragAdminApiUrl // ignore: cast_nullable_to_non_nullable
as String,skipTlsVerification: null == skipTlsVerification ? _self.skipTlsVerification : skipTlsVerification // ignore: cast_nullable_to_non_nullable
as bool,caCertPath: freezed == caCertPath ? _self.caCertPath : caCertPath // ignore: cast_nullable_to_non_nullable
as String?,defaultBucketName: null == defaultBucketName ? _self.defaultBucketName : defaultBucketName // ignore: cast_nullable_to_non_nullable
as String,darkMode: null == darkMode ? _self.darkMode : darkMode // ignore: cast_nullable_to_non_nullable
as bool,availableModels: null == availableModels ? _self._availableModels : availableModels // ignore: cast_nullable_to_non_nullable
as List<String>,availableEmbeddingModels: null == availableEmbeddingModels ? _self._availableEmbeddingModels : availableEmbeddingModels // ignore: cast_nullable_to_non_nullable
as List<String>,memoryExplorerEnabled: null == memoryExplorerEnabled ? _self.memoryExplorerEnabled : memoryExplorerEnabled // ignore: cast_nullable_to_non_nullable
as bool,modelComparisonEnabled: null == modelComparisonEnabled ? _self.modelComparisonEnabled : modelComparisonEnabled // ignore: cast_nullable_to_non_nullable
as bool,promptTimeoutSeconds: null == promptTimeoutSeconds ? _self.promptTimeoutSeconds : promptTimeoutSeconds // ignore: cast_nullable_to_non_nullable
as int,connectTimeoutSeconds: null == connectTimeoutSeconds ? _self.connectTimeoutSeconds : connectTimeoutSeconds // ignore: cast_nullable_to_non_nullable
as int,receiveTimeoutSeconds: null == receiveTimeoutSeconds ? _self.receiveTimeoutSeconds : receiveTimeoutSeconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
