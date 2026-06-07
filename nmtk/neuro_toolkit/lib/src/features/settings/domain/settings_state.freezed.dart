// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'settings_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SettingsState {
  bool get telemetryEnabled;
  String? get remoteEndpoint;
  ThemeMode get themeMode;
  bool get isHighContrast;
  double get fontSizeFactor;
  LogLevel get logLevel;
  Map<String, Map<String, dynamic>> get moduleSettings;
  String? get launcherControlApiBaseUrl;

  /// Create a copy of SettingsState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $SettingsStateCopyWith<SettingsState> get copyWith =>
      _$SettingsStateCopyWithImpl<SettingsState>(
          this as SettingsState, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is SettingsState &&
            (identical(other.telemetryEnabled, telemetryEnabled) ||
                other.telemetryEnabled == telemetryEnabled) &&
            (identical(other.remoteEndpoint, remoteEndpoint) ||
                other.remoteEndpoint == remoteEndpoint) &&
            (identical(other.themeMode, themeMode) ||
                other.themeMode == themeMode) &&
            (identical(other.isHighContrast, isHighContrast) ||
                other.isHighContrast == isHighContrast) &&
            (identical(other.fontSizeFactor, fontSizeFactor) ||
                other.fontSizeFactor == fontSizeFactor) &&
            (identical(other.logLevel, logLevel) ||
                other.logLevel == logLevel) &&
            const DeepCollectionEquality()
                .equals(other.moduleSettings, moduleSettings) &&
            (identical(other.launcherControlApiBaseUrl,
                    launcherControlApiBaseUrl) ||
                other.launcherControlApiBaseUrl == launcherControlApiBaseUrl));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      telemetryEnabled,
      remoteEndpoint,
      themeMode,
      isHighContrast,
      fontSizeFactor,
      logLevel,
      const DeepCollectionEquality().hash(moduleSettings),
      launcherControlApiBaseUrl);

  @override
  String toString() {
    return 'SettingsState(telemetryEnabled: $telemetryEnabled, remoteEndpoint: $remoteEndpoint, themeMode: $themeMode, isHighContrast: $isHighContrast, fontSizeFactor: $fontSizeFactor, logLevel: $logLevel, moduleSettings: $moduleSettings, launcherControlApiBaseUrl: $launcherControlApiBaseUrl)';
  }
}

/// @nodoc
abstract mixin class $SettingsStateCopyWith<$Res> {
  factory $SettingsStateCopyWith(
          SettingsState value, $Res Function(SettingsState) _then) =
      _$SettingsStateCopyWithImpl;
  @useResult
  $Res call(
      {bool telemetryEnabled,
      String? remoteEndpoint,
      ThemeMode themeMode,
      bool isHighContrast,
      double fontSizeFactor,
      LogLevel logLevel,
      Map<String, Map<String, dynamic>> moduleSettings,
      String? launcherControlApiBaseUrl});
}

/// @nodoc
class _$SettingsStateCopyWithImpl<$Res>
    implements $SettingsStateCopyWith<$Res> {
  _$SettingsStateCopyWithImpl(this._self, this._then);

  final SettingsState _self;
  final $Res Function(SettingsState) _then;

  /// Create a copy of SettingsState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? telemetryEnabled = null,
    Object? remoteEndpoint = freezed,
    Object? themeMode = null,
    Object? isHighContrast = null,
    Object? fontSizeFactor = null,
    Object? logLevel = null,
    Object? moduleSettings = null,
    Object? launcherControlApiBaseUrl = freezed,
  }) {
    return _then(_self.copyWith(
      telemetryEnabled: null == telemetryEnabled
          ? _self.telemetryEnabled
          : telemetryEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      remoteEndpoint: freezed == remoteEndpoint
          ? _self.remoteEndpoint
          : remoteEndpoint // ignore: cast_nullable_to_non_nullable
              as String?,
      themeMode: null == themeMode
          ? _self.themeMode
          : themeMode // ignore: cast_nullable_to_non_nullable
              as ThemeMode,
      isHighContrast: null == isHighContrast
          ? _self.isHighContrast
          : isHighContrast // ignore: cast_nullable_to_non_nullable
              as bool,
      fontSizeFactor: null == fontSizeFactor
          ? _self.fontSizeFactor
          : fontSizeFactor // ignore: cast_nullable_to_non_nullable
              as double,
      logLevel: null == logLevel
          ? _self.logLevel
          : logLevel // ignore: cast_nullable_to_non_nullable
              as LogLevel,
      moduleSettings: null == moduleSettings
          ? _self.moduleSettings
          : moduleSettings // ignore: cast_nullable_to_non_nullable
              as Map<String, Map<String, dynamic>>,
      launcherControlApiBaseUrl: freezed == launcherControlApiBaseUrl
          ? _self.launcherControlApiBaseUrl
          : launcherControlApiBaseUrl // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [SettingsState].
extension SettingsStatePatterns on SettingsState {
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

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>(
    TResult Function(_SettingsState value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _SettingsState() when $default != null:
        return $default(_that);
      case _:
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

  @optionalTypeArgs
  TResult map<TResult extends Object?>(
    TResult Function(_SettingsState value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SettingsState():
        return $default(_that);
      case _:
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

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>(
    TResult? Function(_SettingsState value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SettingsState() when $default != null:
        return $default(_that);
      case _:
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

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>(
    TResult Function(
            bool telemetryEnabled,
            String? remoteEndpoint,
            ThemeMode themeMode,
            bool isHighContrast,
            double fontSizeFactor,
            LogLevel logLevel,
            Map<String, Map<String, dynamic>> moduleSettings,
            String? launcherControlApiBaseUrl)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _SettingsState() when $default != null:
        return $default(
            _that.telemetryEnabled,
            _that.remoteEndpoint,
            _that.themeMode,
            _that.isHighContrast,
            _that.fontSizeFactor,
            _that.logLevel,
            _that.moduleSettings,
            _that.launcherControlApiBaseUrl);
      case _:
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

  @optionalTypeArgs
  TResult when<TResult extends Object?>(
    TResult Function(
            bool telemetryEnabled,
            String? remoteEndpoint,
            ThemeMode themeMode,
            bool isHighContrast,
            double fontSizeFactor,
            LogLevel logLevel,
            Map<String, Map<String, dynamic>> moduleSettings,
            String? launcherControlApiBaseUrl)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SettingsState():
        return $default(
            _that.telemetryEnabled,
            _that.remoteEndpoint,
            _that.themeMode,
            _that.isHighContrast,
            _that.fontSizeFactor,
            _that.logLevel,
            _that.moduleSettings,
            _that.launcherControlApiBaseUrl);
      case _:
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

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>(
    TResult? Function(
            bool telemetryEnabled,
            String? remoteEndpoint,
            ThemeMode themeMode,
            bool isHighContrast,
            double fontSizeFactor,
            LogLevel logLevel,
            Map<String, Map<String, dynamic>> moduleSettings,
            String? launcherControlApiBaseUrl)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SettingsState() when $default != null:
        return $default(
            _that.telemetryEnabled,
            _that.remoteEndpoint,
            _that.themeMode,
            _that.isHighContrast,
            _that.fontSizeFactor,
            _that.logLevel,
            _that.moduleSettings,
            _that.launcherControlApiBaseUrl);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _SettingsState implements SettingsState {
  const _SettingsState(
      {this.telemetryEnabled = false,
      this.remoteEndpoint,
      this.themeMode = ThemeMode.system,
      this.isHighContrast = false,
      this.fontSizeFactor = 1.0,
      this.logLevel = LogLevel.info,
      final Map<String, Map<String, dynamic>> moduleSettings = const {},
      this.launcherControlApiBaseUrl})
      : _moduleSettings = moduleSettings;

  @override
  @JsonKey()
  final bool telemetryEnabled;
  @override
  final String? remoteEndpoint;
  @override
  @JsonKey()
  final ThemeMode themeMode;
  @override
  @JsonKey()
  final bool isHighContrast;
  @override
  @JsonKey()
  final double fontSizeFactor;
  @override
  @JsonKey()
  final LogLevel logLevel;
  final Map<String, Map<String, dynamic>> _moduleSettings;
  @override
  @JsonKey()
  Map<String, Map<String, dynamic>> get moduleSettings {
    if (_moduleSettings is EqualUnmodifiableMapView) return _moduleSettings;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_moduleSettings);
  }

  @override
  final String? launcherControlApiBaseUrl;

  /// Create a copy of SettingsState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$SettingsStateCopyWith<_SettingsState> get copyWith =>
      __$SettingsStateCopyWithImpl<_SettingsState>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _SettingsState &&
            (identical(other.telemetryEnabled, telemetryEnabled) ||
                other.telemetryEnabled == telemetryEnabled) &&
            (identical(other.remoteEndpoint, remoteEndpoint) ||
                other.remoteEndpoint == remoteEndpoint) &&
            (identical(other.themeMode, themeMode) ||
                other.themeMode == themeMode) &&
            (identical(other.isHighContrast, isHighContrast) ||
                other.isHighContrast == isHighContrast) &&
            (identical(other.fontSizeFactor, fontSizeFactor) ||
                other.fontSizeFactor == fontSizeFactor) &&
            (identical(other.logLevel, logLevel) ||
                other.logLevel == logLevel) &&
            const DeepCollectionEquality()
                .equals(other._moduleSettings, _moduleSettings) &&
            (identical(other.launcherControlApiBaseUrl,
                    launcherControlApiBaseUrl) ||
                other.launcherControlApiBaseUrl == launcherControlApiBaseUrl));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      telemetryEnabled,
      remoteEndpoint,
      themeMode,
      isHighContrast,
      fontSizeFactor,
      logLevel,
      const DeepCollectionEquality().hash(_moduleSettings),
      launcherControlApiBaseUrl);

  @override
  String toString() {
    return 'SettingsState(telemetryEnabled: $telemetryEnabled, remoteEndpoint: $remoteEndpoint, themeMode: $themeMode, isHighContrast: $isHighContrast, fontSizeFactor: $fontSizeFactor, logLevel: $logLevel, moduleSettings: $moduleSettings, launcherControlApiBaseUrl: $launcherControlApiBaseUrl)';
  }
}

/// @nodoc
abstract mixin class _$SettingsStateCopyWith<$Res>
    implements $SettingsStateCopyWith<$Res> {
  factory _$SettingsStateCopyWith(
          _SettingsState value, $Res Function(_SettingsState) _then) =
      __$SettingsStateCopyWithImpl;
  @override
  @useResult
  $Res call(
      {bool telemetryEnabled,
      String? remoteEndpoint,
      ThemeMode themeMode,
      bool isHighContrast,
      double fontSizeFactor,
      LogLevel logLevel,
      Map<String, Map<String, dynamic>> moduleSettings,
      String? launcherControlApiBaseUrl});
}

/// @nodoc
class __$SettingsStateCopyWithImpl<$Res>
    implements _$SettingsStateCopyWith<$Res> {
  __$SettingsStateCopyWithImpl(this._self, this._then);

  final _SettingsState _self;
  final $Res Function(_SettingsState) _then;

  /// Create a copy of SettingsState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? telemetryEnabled = null,
    Object? remoteEndpoint = freezed,
    Object? themeMode = null,
    Object? isHighContrast = null,
    Object? fontSizeFactor = null,
    Object? logLevel = null,
    Object? moduleSettings = null,
    Object? launcherControlApiBaseUrl = freezed,
  }) {
    return _then(_SettingsState(
      telemetryEnabled: null == telemetryEnabled
          ? _self.telemetryEnabled
          : telemetryEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      remoteEndpoint: freezed == remoteEndpoint
          ? _self.remoteEndpoint
          : remoteEndpoint // ignore: cast_nullable_to_non_nullable
              as String?,
      themeMode: null == themeMode
          ? _self.themeMode
          : themeMode // ignore: cast_nullable_to_non_nullable
              as ThemeMode,
      isHighContrast: null == isHighContrast
          ? _self.isHighContrast
          : isHighContrast // ignore: cast_nullable_to_non_nullable
              as bool,
      fontSizeFactor: null == fontSizeFactor
          ? _self.fontSizeFactor
          : fontSizeFactor // ignore: cast_nullable_to_non_nullable
              as double,
      logLevel: null == logLevel
          ? _self.logLevel
          : logLevel // ignore: cast_nullable_to_non_nullable
              as LogLevel,
      moduleSettings: null == moduleSettings
          ? _self._moduleSettings
          : moduleSettings // ignore: cast_nullable_to_non_nullable
              as Map<String, Map<String, dynamic>>,
      launcherControlApiBaseUrl: freezed == launcherControlApiBaseUrl
          ? _self.launcherControlApiBaseUrl
          : launcherControlApiBaseUrl // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

// dart format on
