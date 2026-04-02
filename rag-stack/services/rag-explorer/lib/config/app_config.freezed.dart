// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

AppConfig _$AppConfigFromJson(Map<String, dynamic> json) {
  return _AppConfig.fromJson(json);
}

/// @nodoc
mixin _$AppConfig {
  String get llmGatewayUrl => throw _privateConstructorUsedError;
  String get ragIngestionUrl => throw _privateConstructorUsedError;
  String get objectStoreMgrUrl => throw _privateConstructorUsedError;
  String get dbAdapterUrl => throw _privateConstructorUsedError;
  String get qdrantAdapterUrl => throw _privateConstructorUsedError;
  String get memoryControllerUrl => throw _privateConstructorUsedError;
  String get grafanaUrl => throw _privateConstructorUsedError;
  bool get skipTlsVerification => throw _privateConstructorUsedError;
  String? get caCertPath => throw _privateConstructorUsedError;
  bool get darkMode => throw _privateConstructorUsedError;
  List<String> get availableModels => throw _privateConstructorUsedError;
  bool get memoryExplorerEnabled => throw _privateConstructorUsedError;
  bool get modelComparisonEnabled => throw _privateConstructorUsedError;

  /// Serializes this AppConfig to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of AppConfig
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AppConfigCopyWith<AppConfig> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AppConfigCopyWith<$Res> {
  factory $AppConfigCopyWith(AppConfig value, $Res Function(AppConfig) then) =
      _$AppConfigCopyWithImpl<$Res, AppConfig>;
  @useResult
  $Res call(
      {String llmGatewayUrl,
      String ragIngestionUrl,
      String objectStoreMgrUrl,
      String dbAdapterUrl,
      String qdrantAdapterUrl,
      String memoryControllerUrl,
      String grafanaUrl,
      bool skipTlsVerification,
      String? caCertPath,
      bool darkMode,
      List<String> availableModels,
      bool memoryExplorerEnabled,
      bool modelComparisonEnabled});
}

/// @nodoc
class _$AppConfigCopyWithImpl<$Res, $Val extends AppConfig>
    implements $AppConfigCopyWith<$Res> {
  _$AppConfigCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AppConfig
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? llmGatewayUrl = null,
    Object? ragIngestionUrl = null,
    Object? objectStoreMgrUrl = null,
    Object? dbAdapterUrl = null,
    Object? qdrantAdapterUrl = null,
    Object? memoryControllerUrl = null,
    Object? grafanaUrl = null,
    Object? skipTlsVerification = null,
    Object? caCertPath = freezed,
    Object? darkMode = null,
    Object? availableModels = null,
    Object? memoryExplorerEnabled = null,
    Object? modelComparisonEnabled = null,
  }) {
    return _then(_value.copyWith(
      llmGatewayUrl: null == llmGatewayUrl
          ? _value.llmGatewayUrl
          : llmGatewayUrl // ignore: cast_nullable_to_non_nullable
              as String,
      ragIngestionUrl: null == ragIngestionUrl
          ? _value.ragIngestionUrl
          : ragIngestionUrl // ignore: cast_nullable_to_non_nullable
              as String,
      objectStoreMgrUrl: null == objectStoreMgrUrl
          ? _value.objectStoreMgrUrl
          : objectStoreMgrUrl // ignore: cast_nullable_to_non_nullable
              as String,
      dbAdapterUrl: null == dbAdapterUrl
          ? _value.dbAdapterUrl
          : dbAdapterUrl // ignore: cast_nullable_to_non_nullable
              as String,
      qdrantAdapterUrl: null == qdrantAdapterUrl
          ? _value.qdrantAdapterUrl
          : qdrantAdapterUrl // ignore: cast_nullable_to_non_nullable
              as String,
      memoryControllerUrl: null == memoryControllerUrl
          ? _value.memoryControllerUrl
          : memoryControllerUrl // ignore: cast_nullable_to_non_nullable
              as String,
      grafanaUrl: null == grafanaUrl
          ? _value.grafanaUrl
          : grafanaUrl // ignore: cast_nullable_to_non_nullable
              as String,
      skipTlsVerification: null == skipTlsVerification
          ? _value.skipTlsVerification
          : skipTlsVerification // ignore: cast_nullable_to_non_nullable
              as bool,
      caCertPath: freezed == caCertPath
          ? _value.caCertPath
          : caCertPath // ignore: cast_nullable_to_non_nullable
              as String?,
      darkMode: null == darkMode
          ? _value.darkMode
          : darkMode // ignore: cast_nullable_to_non_nullable
              as bool,
      availableModels: null == availableModels
          ? _value.availableModels
          : availableModels // ignore: cast_nullable_to_non_nullable
              as List<String>,
      memoryExplorerEnabled: null == memoryExplorerEnabled
          ? _value.memoryExplorerEnabled
          : memoryExplorerEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      modelComparisonEnabled: null == modelComparisonEnabled
          ? _value.modelComparisonEnabled
          : modelComparisonEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AppConfigImplCopyWith<$Res>
    implements $AppConfigCopyWith<$Res> {
  factory _$$AppConfigImplCopyWith(
          _$AppConfigImpl value, $Res Function(_$AppConfigImpl) then) =
      __$$AppConfigImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String llmGatewayUrl,
      String ragIngestionUrl,
      String objectStoreMgrUrl,
      String dbAdapterUrl,
      String qdrantAdapterUrl,
      String memoryControllerUrl,
      String grafanaUrl,
      bool skipTlsVerification,
      String? caCertPath,
      bool darkMode,
      List<String> availableModels,
      bool memoryExplorerEnabled,
      bool modelComparisonEnabled});
}

/// @nodoc
class __$$AppConfigImplCopyWithImpl<$Res>
    extends _$AppConfigCopyWithImpl<$Res, _$AppConfigImpl>
    implements _$$AppConfigImplCopyWith<$Res> {
  __$$AppConfigImplCopyWithImpl(
      _$AppConfigImpl _value, $Res Function(_$AppConfigImpl) _then)
      : super(_value, _then);

  /// Create a copy of AppConfig
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? llmGatewayUrl = null,
    Object? ragIngestionUrl = null,
    Object? objectStoreMgrUrl = null,
    Object? dbAdapterUrl = null,
    Object? qdrantAdapterUrl = null,
    Object? memoryControllerUrl = null,
    Object? grafanaUrl = null,
    Object? skipTlsVerification = null,
    Object? caCertPath = freezed,
    Object? darkMode = null,
    Object? availableModels = null,
    Object? memoryExplorerEnabled = null,
    Object? modelComparisonEnabled = null,
  }) {
    return _then(_$AppConfigImpl(
      llmGatewayUrl: null == llmGatewayUrl
          ? _value.llmGatewayUrl
          : llmGatewayUrl // ignore: cast_nullable_to_non_nullable
              as String,
      ragIngestionUrl: null == ragIngestionUrl
          ? _value.ragIngestionUrl
          : ragIngestionUrl // ignore: cast_nullable_to_non_nullable
              as String,
      objectStoreMgrUrl: null == objectStoreMgrUrl
          ? _value.objectStoreMgrUrl
          : objectStoreMgrUrl // ignore: cast_nullable_to_non_nullable
              as String,
      dbAdapterUrl: null == dbAdapterUrl
          ? _value.dbAdapterUrl
          : dbAdapterUrl // ignore: cast_nullable_to_non_nullable
              as String,
      qdrantAdapterUrl: null == qdrantAdapterUrl
          ? _value.qdrantAdapterUrl
          : qdrantAdapterUrl // ignore: cast_nullable_to_non_nullable
              as String,
      memoryControllerUrl: null == memoryControllerUrl
          ? _value.memoryControllerUrl
          : memoryControllerUrl // ignore: cast_nullable_to_non_nullable
              as String,
      grafanaUrl: null == grafanaUrl
          ? _value.grafanaUrl
          : grafanaUrl // ignore: cast_nullable_to_non_nullable
              as String,
      skipTlsVerification: null == skipTlsVerification
          ? _value.skipTlsVerification
          : skipTlsVerification // ignore: cast_nullable_to_non_nullable
              as bool,
      caCertPath: freezed == caCertPath
          ? _value.caCertPath
          : caCertPath // ignore: cast_nullable_to_non_nullable
              as String?,
      darkMode: null == darkMode
          ? _value.darkMode
          : darkMode // ignore: cast_nullable_to_non_nullable
              as bool,
      availableModels: null == availableModels
          ? _value._availableModels
          : availableModels // ignore: cast_nullable_to_non_nullable
              as List<String>,
      memoryExplorerEnabled: null == memoryExplorerEnabled
          ? _value.memoryExplorerEnabled
          : memoryExplorerEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      modelComparisonEnabled: null == modelComparisonEnabled
          ? _value.modelComparisonEnabled
          : modelComparisonEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AppConfigImpl implements _AppConfig {
  const _$AppConfigImpl(
      {required this.llmGatewayUrl,
      required this.ragIngestionUrl,
      required this.objectStoreMgrUrl,
      required this.dbAdapterUrl,
      required this.qdrantAdapterUrl,
      required this.memoryControllerUrl,
      required this.grafanaUrl,
      this.skipTlsVerification = true,
      this.caCertPath,
      this.darkMode = false,
      final List<String> availableModels = const [
        'llama3.1',
        'granite3.1-dense:8b'
      ],
      this.memoryExplorerEnabled = true,
      this.modelComparisonEnabled = true})
      : _availableModels = availableModels;

  factory _$AppConfigImpl.fromJson(Map<String, dynamic> json) =>
      _$$AppConfigImplFromJson(json);

  @override
  final String llmGatewayUrl;
  @override
  final String ragIngestionUrl;
  @override
  final String objectStoreMgrUrl;
  @override
  final String dbAdapterUrl;
  @override
  final String qdrantAdapterUrl;
  @override
  final String memoryControllerUrl;
  @override
  final String grafanaUrl;
  @override
  @JsonKey()
  final bool skipTlsVerification;
  @override
  final String? caCertPath;
  @override
  @JsonKey()
  final bool darkMode;
  final List<String> _availableModels;
  @override
  @JsonKey()
  List<String> get availableModels {
    if (_availableModels is EqualUnmodifiableListView) return _availableModels;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_availableModels);
  }

  @override
  @JsonKey()
  final bool memoryExplorerEnabled;
  @override
  @JsonKey()
  final bool modelComparisonEnabled;

  @override
  String toString() {
    return 'AppConfig(llmGatewayUrl: $llmGatewayUrl, ragIngestionUrl: $ragIngestionUrl, objectStoreMgrUrl: $objectStoreMgrUrl, dbAdapterUrl: $dbAdapterUrl, qdrantAdapterUrl: $qdrantAdapterUrl, memoryControllerUrl: $memoryControllerUrl, grafanaUrl: $grafanaUrl, skipTlsVerification: $skipTlsVerification, caCertPath: $caCertPath, darkMode: $darkMode, availableModels: $availableModels, memoryExplorerEnabled: $memoryExplorerEnabled, modelComparisonEnabled: $modelComparisonEnabled)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AppConfigImpl &&
            (identical(other.llmGatewayUrl, llmGatewayUrl) ||
                other.llmGatewayUrl == llmGatewayUrl) &&
            (identical(other.ragIngestionUrl, ragIngestionUrl) ||
                other.ragIngestionUrl == ragIngestionUrl) &&
            (identical(other.objectStoreMgrUrl, objectStoreMgrUrl) ||
                other.objectStoreMgrUrl == objectStoreMgrUrl) &&
            (identical(other.dbAdapterUrl, dbAdapterUrl) ||
                other.dbAdapterUrl == dbAdapterUrl) &&
            (identical(other.qdrantAdapterUrl, qdrantAdapterUrl) ||
                other.qdrantAdapterUrl == qdrantAdapterUrl) &&
            (identical(other.memoryControllerUrl, memoryControllerUrl) ||
                other.memoryControllerUrl == memoryControllerUrl) &&
            (identical(other.grafanaUrl, grafanaUrl) ||
                other.grafanaUrl == grafanaUrl) &&
            (identical(other.skipTlsVerification, skipTlsVerification) ||
                other.skipTlsVerification == skipTlsVerification) &&
            (identical(other.caCertPath, caCertPath) ||
                other.caCertPath == caCertPath) &&
            (identical(other.darkMode, darkMode) ||
                other.darkMode == darkMode) &&
            const DeepCollectionEquality()
                .equals(other._availableModels, _availableModels) &&
            (identical(other.memoryExplorerEnabled, memoryExplorerEnabled) ||
                other.memoryExplorerEnabled == memoryExplorerEnabled) &&
            (identical(other.modelComparisonEnabled, modelComparisonEnabled) ||
                other.modelComparisonEnabled == modelComparisonEnabled));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      llmGatewayUrl,
      ragIngestionUrl,
      objectStoreMgrUrl,
      dbAdapterUrl,
      qdrantAdapterUrl,
      memoryControllerUrl,
      grafanaUrl,
      skipTlsVerification,
      caCertPath,
      darkMode,
      const DeepCollectionEquality().hash(_availableModels),
      memoryExplorerEnabled,
      modelComparisonEnabled);

  /// Create a copy of AppConfig
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AppConfigImplCopyWith<_$AppConfigImpl> get copyWith =>
      __$$AppConfigImplCopyWithImpl<_$AppConfigImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AppConfigImplToJson(
      this,
    );
  }
}

abstract class _AppConfig implements AppConfig {
  const factory _AppConfig(
      {required final String llmGatewayUrl,
      required final String ragIngestionUrl,
      required final String objectStoreMgrUrl,
      required final String dbAdapterUrl,
      required final String qdrantAdapterUrl,
      required final String memoryControllerUrl,
      required final String grafanaUrl,
      final bool skipTlsVerification,
      final String? caCertPath,
      final bool darkMode,
      final List<String> availableModels,
      final bool memoryExplorerEnabled,
      final bool modelComparisonEnabled}) = _$AppConfigImpl;

  factory _AppConfig.fromJson(Map<String, dynamic> json) =
      _$AppConfigImpl.fromJson;

  @override
  String get llmGatewayUrl;
  @override
  String get ragIngestionUrl;
  @override
  String get objectStoreMgrUrl;
  @override
  String get dbAdapterUrl;
  @override
  String get qdrantAdapterUrl;
  @override
  String get memoryControllerUrl;
  @override
  String get grafanaUrl;
  @override
  bool get skipTlsVerification;
  @override
  String? get caCertPath;
  @override
  bool get darkMode;
  @override
  List<String> get availableModels;
  @override
  bool get memoryExplorerEnabled;
  @override
  bool get modelComparisonEnabled;

  /// Create a copy of AppConfig
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AppConfigImplCopyWith<_$AppConfigImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
