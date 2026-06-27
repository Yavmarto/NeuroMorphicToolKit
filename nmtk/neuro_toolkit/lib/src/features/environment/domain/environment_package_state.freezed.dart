// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'environment_package_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$EnvironmentPackageState {
  bool get loading;
  List<PackageInfo> get packages;
  String? get error;

  /// Create a copy of EnvironmentPackageState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $EnvironmentPackageStateCopyWith<EnvironmentPackageState> get copyWith =>
      _$EnvironmentPackageStateCopyWithImpl<EnvironmentPackageState>(
          this as EnvironmentPackageState, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is EnvironmentPackageState &&
            (identical(other.loading, loading) || other.loading == loading) &&
            const DeepCollectionEquality().equals(other.packages, packages) &&
            (identical(other.error, error) || other.error == error));
  }

  @override
  int get hashCode => Object.hash(runtimeType, loading,
      const DeepCollectionEquality().hash(packages), error);

  @override
  String toString() {
    return 'EnvironmentPackageState(loading: $loading, packages: $packages, error: $error)';
  }
}

/// @nodoc
abstract mixin class $EnvironmentPackageStateCopyWith<$Res> {
  factory $EnvironmentPackageStateCopyWith(EnvironmentPackageState value,
          $Res Function(EnvironmentPackageState) _then) =
      _$EnvironmentPackageStateCopyWithImpl;
  @useResult
  $Res call({bool loading, List<PackageInfo> packages, String? error});
}

/// @nodoc
class _$EnvironmentPackageStateCopyWithImpl<$Res>
    implements $EnvironmentPackageStateCopyWith<$Res> {
  _$EnvironmentPackageStateCopyWithImpl(this._self, this._then);

  final EnvironmentPackageState _self;
  final $Res Function(EnvironmentPackageState) _then;

  /// Create a copy of EnvironmentPackageState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? loading = null,
    Object? packages = null,
    Object? error = freezed,
  }) {
    return _then(_self.copyWith(
      loading: null == loading
          ? _self.loading
          : loading // ignore: cast_nullable_to_non_nullable
              as bool,
      packages: null == packages
          ? _self.packages
          : packages // ignore: cast_nullable_to_non_nullable
              as List<PackageInfo>,
      error: freezed == error
          ? _self.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [EnvironmentPackageState].
extension EnvironmentPackageStatePatterns on EnvironmentPackageState {
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
    TResult Function(_EnvironmentPackageState value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _EnvironmentPackageState() when $default != null:
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
    TResult Function(_EnvironmentPackageState value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _EnvironmentPackageState():
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
    TResult? Function(_EnvironmentPackageState value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _EnvironmentPackageState() when $default != null:
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
    TResult Function(bool loading, List<PackageInfo> packages, String? error)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _EnvironmentPackageState() when $default != null:
        return $default(_that.loading, _that.packages, _that.error);
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
    TResult Function(bool loading, List<PackageInfo> packages, String? error)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _EnvironmentPackageState():
        return $default(_that.loading, _that.packages, _that.error);
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
    TResult? Function(bool loading, List<PackageInfo> packages, String? error)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _EnvironmentPackageState() when $default != null:
        return $default(_that.loading, _that.packages, _that.error);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _EnvironmentPackageState implements EnvironmentPackageState {
  const _EnvironmentPackageState(
      {this.loading = false,
      final List<PackageInfo> packages = const [],
      this.error})
      : _packages = packages;

  @override
  @JsonKey()
  final bool loading;
  final List<PackageInfo> _packages;
  @override
  @JsonKey()
  List<PackageInfo> get packages {
    if (_packages is EqualUnmodifiableListView) return _packages;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_packages);
  }

  @override
  final String? error;

  /// Create a copy of EnvironmentPackageState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$EnvironmentPackageStateCopyWith<_EnvironmentPackageState> get copyWith =>
      __$EnvironmentPackageStateCopyWithImpl<_EnvironmentPackageState>(
          this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _EnvironmentPackageState &&
            (identical(other.loading, loading) || other.loading == loading) &&
            const DeepCollectionEquality().equals(other._packages, _packages) &&
            (identical(other.error, error) || other.error == error));
  }

  @override
  int get hashCode => Object.hash(runtimeType, loading,
      const DeepCollectionEquality().hash(_packages), error);

  @override
  String toString() {
    return 'EnvironmentPackageState(loading: $loading, packages: $packages, error: $error)';
  }
}

/// @nodoc
abstract mixin class _$EnvironmentPackageStateCopyWith<$Res>
    implements $EnvironmentPackageStateCopyWith<$Res> {
  factory _$EnvironmentPackageStateCopyWith(_EnvironmentPackageState value,
          $Res Function(_EnvironmentPackageState) _then) =
      __$EnvironmentPackageStateCopyWithImpl;
  @override
  @useResult
  $Res call({bool loading, List<PackageInfo> packages, String? error});
}

/// @nodoc
class __$EnvironmentPackageStateCopyWithImpl<$Res>
    implements _$EnvironmentPackageStateCopyWith<$Res> {
  __$EnvironmentPackageStateCopyWithImpl(this._self, this._then);

  final _EnvironmentPackageState _self;
  final $Res Function(_EnvironmentPackageState) _then;

  /// Create a copy of EnvironmentPackageState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? loading = null,
    Object? packages = null,
    Object? error = freezed,
  }) {
    return _then(_EnvironmentPackageState(
      loading: null == loading
          ? _self.loading
          : loading // ignore: cast_nullable_to_non_nullable
              as bool,
      packages: null == packages
          ? _self._packages
          : packages // ignore: cast_nullable_to_non_nullable
              as List<PackageInfo>,
      error: freezed == error
          ? _self.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
mixin _$EnvironmentExportState {
  bool get loading;
  String get body;
  String get mode;
  String? get error;

  /// Create a copy of EnvironmentExportState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $EnvironmentExportStateCopyWith<EnvironmentExportState> get copyWith =>
      _$EnvironmentExportStateCopyWithImpl<EnvironmentExportState>(
          this as EnvironmentExportState, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is EnvironmentExportState &&
            (identical(other.loading, loading) || other.loading == loading) &&
            (identical(other.body, body) || other.body == body) &&
            (identical(other.mode, mode) || other.mode == mode) &&
            (identical(other.error, error) || other.error == error));
  }

  @override
  int get hashCode => Object.hash(runtimeType, loading, body, mode, error);

  @override
  String toString() {
    return 'EnvironmentExportState(loading: $loading, body: $body, mode: $mode, error: $error)';
  }
}

/// @nodoc
abstract mixin class $EnvironmentExportStateCopyWith<$Res> {
  factory $EnvironmentExportStateCopyWith(EnvironmentExportState value,
          $Res Function(EnvironmentExportState) _then) =
      _$EnvironmentExportStateCopyWithImpl;
  @useResult
  $Res call({bool loading, String body, String mode, String? error});
}

/// @nodoc
class _$EnvironmentExportStateCopyWithImpl<$Res>
    implements $EnvironmentExportStateCopyWith<$Res> {
  _$EnvironmentExportStateCopyWithImpl(this._self, this._then);

  final EnvironmentExportState _self;
  final $Res Function(EnvironmentExportState) _then;

  /// Create a copy of EnvironmentExportState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? loading = null,
    Object? body = null,
    Object? mode = null,
    Object? error = freezed,
  }) {
    return _then(_self.copyWith(
      loading: null == loading
          ? _self.loading
          : loading // ignore: cast_nullable_to_non_nullable
              as bool,
      body: null == body
          ? _self.body
          : body // ignore: cast_nullable_to_non_nullable
              as String,
      mode: null == mode
          ? _self.mode
          : mode // ignore: cast_nullable_to_non_nullable
              as String,
      error: freezed == error
          ? _self.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [EnvironmentExportState].
extension EnvironmentExportStatePatterns on EnvironmentExportState {
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
    TResult Function(_EnvironmentExportState value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _EnvironmentExportState() when $default != null:
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
    TResult Function(_EnvironmentExportState value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _EnvironmentExportState():
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
    TResult? Function(_EnvironmentExportState value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _EnvironmentExportState() when $default != null:
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
    TResult Function(bool loading, String body, String mode, String? error)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _EnvironmentExportState() when $default != null:
        return $default(_that.loading, _that.body, _that.mode, _that.error);
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
    TResult Function(bool loading, String body, String mode, String? error)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _EnvironmentExportState():
        return $default(_that.loading, _that.body, _that.mode, _that.error);
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
    TResult? Function(bool loading, String body, String mode, String? error)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _EnvironmentExportState() when $default != null:
        return $default(_that.loading, _that.body, _that.mode, _that.error);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _EnvironmentExportState implements EnvironmentExportState {
  const _EnvironmentExportState(
      {this.loading = true, this.body = '', this.mode = 'delta', this.error});

  @override
  @JsonKey()
  final bool loading;
  @override
  @JsonKey()
  final String body;
  @override
  @JsonKey()
  final String mode;
  @override
  final String? error;

  /// Create a copy of EnvironmentExportState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$EnvironmentExportStateCopyWith<_EnvironmentExportState> get copyWith =>
      __$EnvironmentExportStateCopyWithImpl<_EnvironmentExportState>(
          this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _EnvironmentExportState &&
            (identical(other.loading, loading) || other.loading == loading) &&
            (identical(other.body, body) || other.body == body) &&
            (identical(other.mode, mode) || other.mode == mode) &&
            (identical(other.error, error) || other.error == error));
  }

  @override
  int get hashCode => Object.hash(runtimeType, loading, body, mode, error);

  @override
  String toString() {
    return 'EnvironmentExportState(loading: $loading, body: $body, mode: $mode, error: $error)';
  }
}

/// @nodoc
abstract mixin class _$EnvironmentExportStateCopyWith<$Res>
    implements $EnvironmentExportStateCopyWith<$Res> {
  factory _$EnvironmentExportStateCopyWith(_EnvironmentExportState value,
          $Res Function(_EnvironmentExportState) _then) =
      __$EnvironmentExportStateCopyWithImpl;
  @override
  @useResult
  $Res call({bool loading, String body, String mode, String? error});
}

/// @nodoc
class __$EnvironmentExportStateCopyWithImpl<$Res>
    implements _$EnvironmentExportStateCopyWith<$Res> {
  __$EnvironmentExportStateCopyWithImpl(this._self, this._then);

  final _EnvironmentExportState _self;
  final $Res Function(_EnvironmentExportState) _then;

  /// Create a copy of EnvironmentExportState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? loading = null,
    Object? body = null,
    Object? mode = null,
    Object? error = freezed,
  }) {
    return _then(_EnvironmentExportState(
      loading: null == loading
          ? _self.loading
          : loading // ignore: cast_nullable_to_non_nullable
              as bool,
      body: null == body
          ? _self.body
          : body // ignore: cast_nullable_to_non_nullable
              as String,
      mode: null == mode
          ? _self.mode
          : mode // ignore: cast_nullable_to_non_nullable
              as String,
      error: freezed == error
          ? _self.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

// dart format on
