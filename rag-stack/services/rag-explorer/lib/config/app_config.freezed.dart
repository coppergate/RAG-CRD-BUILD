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

 String get llmGatewayUrl; String get ragIngestionUrl; String get objectStoreMgrUrl; String get dbAdapterUrl; String get qdrantAdapterUrl; String get memoryControllerUrl; String get grafanaUrl; String get ragAdminApiUrl; bool get skipTlsVerification; String? get caCertPath; bool get darkMode; List<String> get availableModels; bool get memoryExplorerEnabled; bool get modelComparisonEnabled;
/// Create a copy of AppConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppConfigCopyWith<AppConfig> get copyWith => _$AppConfigCopyWithImpl<AppConfig>(this as AppConfig, _$identity);

  /// Serializes this AppConfig to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppConfig&&(identical(other.llmGatewayUrl, llmGatewayUrl) || other.llmGatewayUrl == llmGatewayUrl)&&(identical(other.ragIngestionUrl, ragIngestionUrl) || other.ragIngestionUrl == ragIngestionUrl)&&(identical(other.objectStoreMgrUrl, objectStoreMgrUrl) || other.objectStoreMgrUrl == objectStoreMgrUrl)&&(identical(other.dbAdapterUrl, dbAdapterUrl) || other.dbAdapterUrl == dbAdapterUrl)&&(identical(other.qdrantAdapterUrl, qdrantAdapterUrl) || other.qdrantAdapterUrl == qdrantAdapterUrl)&&(identical(other.memoryControllerUrl, memoryControllerUrl) || other.memoryControllerUrl == memoryControllerUrl)&&(identical(other.grafanaUrl, grafanaUrl) || other.grafanaUrl == grafanaUrl)&&(identical(other.ragAdminApiUrl, ragAdminApiUrl) || other.ragAdminApiUrl == ragAdminApiUrl)&&(identical(other.skipTlsVerification, skipTlsVerification) || other.skipTlsVerification == skipTlsVerification)&&(identical(other.caCertPath, caCertPath) || other.caCertPath == caCertPath)&&(identical(other.darkMode, darkMode) || other.darkMode == darkMode)&&const DeepCollectionEquality().equals(other.availableModels, availableModels)&&(identical(other.memoryExplorerEnabled, memoryExplorerEnabled) || other.memoryExplorerEnabled == memoryExplorerEnabled)&&(identical(other.modelComparisonEnabled, modelComparisonEnabled) || other.modelComparisonEnabled == modelComparisonEnabled));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,llmGatewayUrl,ragIngestionUrl,objectStoreMgrUrl,dbAdapterUrl,qdrantAdapterUrl,memoryControllerUrl,grafanaUrl,ragAdminApiUrl,skipTlsVerification,caCertPath,darkMode,const DeepCollectionEquality().hash(availableModels),memoryExplorerEnabled,modelComparisonEnabled);

@override
String toString() {
  return 'AppConfig(llmGatewayUrl: $llmGatewayUrl, ragIngestionUrl: $ragIngestionUrl, objectStoreMgrUrl: $objectStoreMgrUrl, dbAdapterUrl: $dbAdapterUrl, qdrantAdapterUrl: $qdrantAdapterUrl, memoryControllerUrl: $memoryControllerUrl, grafanaUrl: $grafanaUrl, ragAdminApiUrl: $ragAdminApiUrl, skipTlsVerification: $skipTlsVerification, caCertPath: $caCertPath, darkMode: $darkMode, availableModels: $availableModels, memoryExplorerEnabled: $memoryExplorerEnabled, modelComparisonEnabled: $modelComparisonEnabled)';
}


}

/// @nodoc
abstract mixin class $AppConfigCopyWith<$Res>  {
  factory $AppConfigCopyWith(AppConfig value, $Res Function(AppConfig) _then) = _$AppConfigCopyWithImpl;
@useResult
$Res call({
 String llmGatewayUrl, String ragIngestionUrl, String objectStoreMgrUrl, String dbAdapterUrl, String qdrantAdapterUrl, String memoryControllerUrl, String grafanaUrl, String ragAdminApiUrl, bool skipTlsVerification, String? caCertPath, bool darkMode, List<String> availableModels, bool memoryExplorerEnabled, bool modelComparisonEnabled
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
@pragma('vm:prefer-inline') @override $Res call({Object? llmGatewayUrl = null,Object? ragIngestionUrl = null,Object? objectStoreMgrUrl = null,Object? dbAdapterUrl = null,Object? qdrantAdapterUrl = null,Object? memoryControllerUrl = null,Object? grafanaUrl = null,Object? ragAdminApiUrl = null,Object? skipTlsVerification = null,Object? caCertPath = freezed,Object? darkMode = null,Object? availableModels = null,Object? memoryExplorerEnabled = null,Object? modelComparisonEnabled = null,}) {
  return _then(_self.copyWith(
llmGatewayUrl: null == llmGatewayUrl ? _self.llmGatewayUrl : llmGatewayUrl // ignore: cast_nullable_to_non_nullable
as String,ragIngestionUrl: null == ragIngestionUrl ? _self.ragIngestionUrl : ragIngestionUrl // ignore: cast_nullable_to_non_nullable
as String,objectStoreMgrUrl: null == objectStoreMgrUrl ? _self.objectStoreMgrUrl : objectStoreMgrUrl // ignore: cast_nullable_to_non_nullable
as String,dbAdapterUrl: null == dbAdapterUrl ? _self.dbAdapterUrl : dbAdapterUrl // ignore: cast_nullable_to_non_nullable
as String,qdrantAdapterUrl: null == qdrantAdapterUrl ? _self.qdrantAdapterUrl : qdrantAdapterUrl // ignore: cast_nullable_to_non_nullable
as String,memoryControllerUrl: null == memoryControllerUrl ? _self.memoryControllerUrl : memoryControllerUrl // ignore: cast_nullable_to_non_nullable
as String,grafanaUrl: null == grafanaUrl ? _self.grafanaUrl : grafanaUrl // ignore: cast_nullable_to_non_nullable
as String,ragAdminApiUrl: null == ragAdminApiUrl ? _self.ragAdminApiUrl : ragAdminApiUrl // ignore: cast_nullable_to_non_nullable
as String,skipTlsVerification: null == skipTlsVerification ? _self.skipTlsVerification : skipTlsVerification // ignore: cast_nullable_to_non_nullable
as bool,caCertPath: freezed == caCertPath ? _self.caCertPath : caCertPath // ignore: cast_nullable_to_non_nullable
as String?,darkMode: null == darkMode ? _self.darkMode : darkMode // ignore: cast_nullable_to_non_nullable
as bool,availableModels: null == availableModels ? _self.availableModels : availableModels // ignore: cast_nullable_to_non_nullable
as List<String>,memoryExplorerEnabled: null == memoryExplorerEnabled ? _self.memoryExplorerEnabled : memoryExplorerEnabled // ignore: cast_nullable_to_non_nullable
as bool,modelComparisonEnabled: null == modelComparisonEnabled ? _self.modelComparisonEnabled : modelComparisonEnabled // ignore: cast_nullable_to_non_nullable
as bool,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String llmGatewayUrl,  String ragIngestionUrl,  String objectStoreMgrUrl,  String dbAdapterUrl,  String qdrantAdapterUrl,  String memoryControllerUrl,  String grafanaUrl,  String ragAdminApiUrl,  bool skipTlsVerification,  String? caCertPath,  bool darkMode,  List<String> availableModels,  bool memoryExplorerEnabled,  bool modelComparisonEnabled)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppConfig() when $default != null:
return $default(_that.llmGatewayUrl,_that.ragIngestionUrl,_that.objectStoreMgrUrl,_that.dbAdapterUrl,_that.qdrantAdapterUrl,_that.memoryControllerUrl,_that.grafanaUrl,_that.ragAdminApiUrl,_that.skipTlsVerification,_that.caCertPath,_that.darkMode,_that.availableModels,_that.memoryExplorerEnabled,_that.modelComparisonEnabled);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String llmGatewayUrl,  String ragIngestionUrl,  String objectStoreMgrUrl,  String dbAdapterUrl,  String qdrantAdapterUrl,  String memoryControllerUrl,  String grafanaUrl,  String ragAdminApiUrl,  bool skipTlsVerification,  String? caCertPath,  bool darkMode,  List<String> availableModels,  bool memoryExplorerEnabled,  bool modelComparisonEnabled)  $default,) {final _that = this;
switch (_that) {
case _AppConfig():
return $default(_that.llmGatewayUrl,_that.ragIngestionUrl,_that.objectStoreMgrUrl,_that.dbAdapterUrl,_that.qdrantAdapterUrl,_that.memoryControllerUrl,_that.grafanaUrl,_that.ragAdminApiUrl,_that.skipTlsVerification,_that.caCertPath,_that.darkMode,_that.availableModels,_that.memoryExplorerEnabled,_that.modelComparisonEnabled);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String llmGatewayUrl,  String ragIngestionUrl,  String objectStoreMgrUrl,  String dbAdapterUrl,  String qdrantAdapterUrl,  String memoryControllerUrl,  String grafanaUrl,  String ragAdminApiUrl,  bool skipTlsVerification,  String? caCertPath,  bool darkMode,  List<String> availableModels,  bool memoryExplorerEnabled,  bool modelComparisonEnabled)?  $default,) {final _that = this;
switch (_that) {
case _AppConfig() when $default != null:
return $default(_that.llmGatewayUrl,_that.ragIngestionUrl,_that.objectStoreMgrUrl,_that.dbAdapterUrl,_that.qdrantAdapterUrl,_that.memoryControllerUrl,_that.grafanaUrl,_that.ragAdminApiUrl,_that.skipTlsVerification,_that.caCertPath,_that.darkMode,_that.availableModels,_that.memoryExplorerEnabled,_that.modelComparisonEnabled);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AppConfig implements AppConfig {
  const _AppConfig({required this.llmGatewayUrl, required this.ragIngestionUrl, required this.objectStoreMgrUrl, required this.dbAdapterUrl, required this.qdrantAdapterUrl, required this.memoryControllerUrl, required this.grafanaUrl, required this.ragAdminApiUrl, this.skipTlsVerification = true, this.caCertPath, this.darkMode = false, final  List<String> availableModels = const ['llama3.1', 'granite3.1-dense:8b'], this.memoryExplorerEnabled = true, this.modelComparisonEnabled = true}): _availableModels = availableModels;
  factory _AppConfig.fromJson(Map<String, dynamic> json) => _$AppConfigFromJson(json);

@override final  String llmGatewayUrl;
@override final  String ragIngestionUrl;
@override final  String objectStoreMgrUrl;
@override final  String dbAdapterUrl;
@override final  String qdrantAdapterUrl;
@override final  String memoryControllerUrl;
@override final  String grafanaUrl;
@override final  String ragAdminApiUrl;
@override@JsonKey() final  bool skipTlsVerification;
@override final  String? caCertPath;
@override@JsonKey() final  bool darkMode;
 final  List<String> _availableModels;
@override@JsonKey() List<String> get availableModels {
  if (_availableModels is EqualUnmodifiableListView) return _availableModels;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_availableModels);
}

@override@JsonKey() final  bool memoryExplorerEnabled;
@override@JsonKey() final  bool modelComparisonEnabled;

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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppConfig&&(identical(other.llmGatewayUrl, llmGatewayUrl) || other.llmGatewayUrl == llmGatewayUrl)&&(identical(other.ragIngestionUrl, ragIngestionUrl) || other.ragIngestionUrl == ragIngestionUrl)&&(identical(other.objectStoreMgrUrl, objectStoreMgrUrl) || other.objectStoreMgrUrl == objectStoreMgrUrl)&&(identical(other.dbAdapterUrl, dbAdapterUrl) || other.dbAdapterUrl == dbAdapterUrl)&&(identical(other.qdrantAdapterUrl, qdrantAdapterUrl) || other.qdrantAdapterUrl == qdrantAdapterUrl)&&(identical(other.memoryControllerUrl, memoryControllerUrl) || other.memoryControllerUrl == memoryControllerUrl)&&(identical(other.grafanaUrl, grafanaUrl) || other.grafanaUrl == grafanaUrl)&&(identical(other.ragAdminApiUrl, ragAdminApiUrl) || other.ragAdminApiUrl == ragAdminApiUrl)&&(identical(other.skipTlsVerification, skipTlsVerification) || other.skipTlsVerification == skipTlsVerification)&&(identical(other.caCertPath, caCertPath) || other.caCertPath == caCertPath)&&(identical(other.darkMode, darkMode) || other.darkMode == darkMode)&&const DeepCollectionEquality().equals(other._availableModels, _availableModels)&&(identical(other.memoryExplorerEnabled, memoryExplorerEnabled) || other.memoryExplorerEnabled == memoryExplorerEnabled)&&(identical(other.modelComparisonEnabled, modelComparisonEnabled) || other.modelComparisonEnabled == modelComparisonEnabled));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,llmGatewayUrl,ragIngestionUrl,objectStoreMgrUrl,dbAdapterUrl,qdrantAdapterUrl,memoryControllerUrl,grafanaUrl,ragAdminApiUrl,skipTlsVerification,caCertPath,darkMode,const DeepCollectionEquality().hash(_availableModels),memoryExplorerEnabled,modelComparisonEnabled);

@override
String toString() {
  return 'AppConfig(llmGatewayUrl: $llmGatewayUrl, ragIngestionUrl: $ragIngestionUrl, objectStoreMgrUrl: $objectStoreMgrUrl, dbAdapterUrl: $dbAdapterUrl, qdrantAdapterUrl: $qdrantAdapterUrl, memoryControllerUrl: $memoryControllerUrl, grafanaUrl: $grafanaUrl, ragAdminApiUrl: $ragAdminApiUrl, skipTlsVerification: $skipTlsVerification, caCertPath: $caCertPath, darkMode: $darkMode, availableModels: $availableModels, memoryExplorerEnabled: $memoryExplorerEnabled, modelComparisonEnabled: $modelComparisonEnabled)';
}


}

/// @nodoc
abstract mixin class _$AppConfigCopyWith<$Res> implements $AppConfigCopyWith<$Res> {
  factory _$AppConfigCopyWith(_AppConfig value, $Res Function(_AppConfig) _then) = __$AppConfigCopyWithImpl;
@override @useResult
$Res call({
 String llmGatewayUrl, String ragIngestionUrl, String objectStoreMgrUrl, String dbAdapterUrl, String qdrantAdapterUrl, String memoryControllerUrl, String grafanaUrl, String ragAdminApiUrl, bool skipTlsVerification, String? caCertPath, bool darkMode, List<String> availableModels, bool memoryExplorerEnabled, bool modelComparisonEnabled
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
@override @pragma('vm:prefer-inline') $Res call({Object? llmGatewayUrl = null,Object? ragIngestionUrl = null,Object? objectStoreMgrUrl = null,Object? dbAdapterUrl = null,Object? qdrantAdapterUrl = null,Object? memoryControllerUrl = null,Object? grafanaUrl = null,Object? ragAdminApiUrl = null,Object? skipTlsVerification = null,Object? caCertPath = freezed,Object? darkMode = null,Object? availableModels = null,Object? memoryExplorerEnabled = null,Object? modelComparisonEnabled = null,}) {
  return _then(_AppConfig(
llmGatewayUrl: null == llmGatewayUrl ? _self.llmGatewayUrl : llmGatewayUrl // ignore: cast_nullable_to_non_nullable
as String,ragIngestionUrl: null == ragIngestionUrl ? _self.ragIngestionUrl : ragIngestionUrl // ignore: cast_nullable_to_non_nullable
as String,objectStoreMgrUrl: null == objectStoreMgrUrl ? _self.objectStoreMgrUrl : objectStoreMgrUrl // ignore: cast_nullable_to_non_nullable
as String,dbAdapterUrl: null == dbAdapterUrl ? _self.dbAdapterUrl : dbAdapterUrl // ignore: cast_nullable_to_non_nullable
as String,qdrantAdapterUrl: null == qdrantAdapterUrl ? _self.qdrantAdapterUrl : qdrantAdapterUrl // ignore: cast_nullable_to_non_nullable
as String,memoryControllerUrl: null == memoryControllerUrl ? _self.memoryControllerUrl : memoryControllerUrl // ignore: cast_nullable_to_non_nullable
as String,grafanaUrl: null == grafanaUrl ? _self.grafanaUrl : grafanaUrl // ignore: cast_nullable_to_non_nullable
as String,ragAdminApiUrl: null == ragAdminApiUrl ? _self.ragAdminApiUrl : ragAdminApiUrl // ignore: cast_nullable_to_non_nullable
as String,skipTlsVerification: null == skipTlsVerification ? _self.skipTlsVerification : skipTlsVerification // ignore: cast_nullable_to_non_nullable
as bool,caCertPath: freezed == caCertPath ? _self.caCertPath : caCertPath // ignore: cast_nullable_to_non_nullable
as String?,darkMode: null == darkMode ? _self.darkMode : darkMode // ignore: cast_nullable_to_non_nullable
as bool,availableModels: null == availableModels ? _self._availableModels : availableModels // ignore: cast_nullable_to_non_nullable
as List<String>,memoryExplorerEnabled: null == memoryExplorerEnabled ? _self.memoryExplorerEnabled : memoryExplorerEnabled // ignore: cast_nullable_to_non_nullable
as bool,modelComparisonEnabled: null == modelComparisonEnabled ? _self.modelComparisonEnabled : modelComparisonEnabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
