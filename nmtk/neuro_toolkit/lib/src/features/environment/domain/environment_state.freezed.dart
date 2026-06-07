// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'environment_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$EnvironmentState {
  List<EnvironmentInfo> get environments;
  bool get busy;
  String? get activeOperation;

  /// Create a copy of EnvironmentState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $EnvironmentStateCopyWith<EnvironmentState> get copyWith =>
      _$EnvironmentStateCopyWithImpl<EnvironmentState>(
          this as EnvironmentState, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is EnvironmentState &&
            const DeepCollectionEquality()
                .equals(other.environments, environments) &&
            (identical(other.busy, busy) || other.busy == busy) &&
            (identical(other.activeOperation, activeOperation) ||
                other.activeOperation == activeOperation));
  }

  @override
  int get hashCode => Object.hash(runtimeType,
      const DeepCollectionEquality().hash(environments), busy, activeOperation);

  @override
  String toString() {
    return 'EnvironmentState(environments: $environments, busy: $busy, activeOperation: $activeOperation)';
  }
}

/// @nodoc
abstract mixin class $EnvironmentStateCopyWith<$Res> {
  factory $EnvironmentStateCopyWith(
          EnvironmentState value, $Res Function(EnvironmentState) _then) =
      _$EnvironmentStateCopyWithImpl;
  @useResult
  $Res call(
      {List<EnvironmentInfo> environments, bool busy, String? activeOperation});
}

/// @nodoc
class _$EnvironmentStateCopyWithImpl<$Res>
    implements $EnvironmentStateCopyWith<$Res> {
  _$EnvironmentStateCopyWithImpl(this._self, this._then);

  final EnvironmentState _self;
  final $Res Function(EnvironmentState) _then;

  /// Create a copy of EnvironmentState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? environments = null,
    Object? busy = null,
    Object? activeOperation = freezed,
  }) {
    return _then(_self.copyWith(
      environments: null == environments
          ? _self.environments
          : environments // ignore: cast_nullable_to_non_nullable
              as List<EnvironmentInfo>,
      busy: null == busy
          ? _self.busy
          : busy // ignore: cast_nullable_to_non_nullable
              as bool,
      activeOperation: freezed == activeOperation
          ? _self.activeOperation
          : activeOperation // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [EnvironmentState].
extension EnvironmentStatePatterns on EnvironmentState {
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
    TResult Function(_EnvironmentState value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _EnvironmentState() when $default != null:
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
    TResult Function(_EnvironmentState value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _EnvironmentState():
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
    TResult? Function(_EnvironmentState value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _EnvironmentState() when $default != null:
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
    TResult Function(List<EnvironmentInfo> environments, bool busy,
            String? activeOperation)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _EnvironmentState() when $default != null:
        return $default(_that.environments, _that.busy, _that.activeOperation);
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
    TResult Function(List<EnvironmentInfo> environments, bool busy,
            String? activeOperation)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _EnvironmentState():
        return $default(_that.environments, _that.busy, _that.activeOperation);
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
    TResult? Function(List<EnvironmentInfo> environments, bool busy,
            String? activeOperation)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _EnvironmentState() when $default != null:
        return $default(_that.environments, _that.busy, _that.activeOperation);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _EnvironmentState implements EnvironmentState {
  const _EnvironmentState(
      {final List<EnvironmentInfo> environments = const [],
      this.busy = false,
      this.activeOperation})
      : _environments = environments;

  final List<EnvironmentInfo> _environments;
  @override
  @JsonKey()
  List<EnvironmentInfo> get environments {
    if (_environments is EqualUnmodifiableListView) return _environments;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_environments);
  }

  @override
  @JsonKey()
  final bool busy;
  @override
  final String? activeOperation;

  /// Create a copy of EnvironmentState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$EnvironmentStateCopyWith<_EnvironmentState> get copyWith =>
      __$EnvironmentStateCopyWithImpl<_EnvironmentState>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _EnvironmentState &&
            const DeepCollectionEquality()
                .equals(other._environments, _environments) &&
            (identical(other.busy, busy) || other.busy == busy) &&
            (identical(other.activeOperation, activeOperation) ||
                other.activeOperation == activeOperation));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_environments),
      busy,
      activeOperation);

  @override
  String toString() {
    return 'EnvironmentState(environments: $environments, busy: $busy, activeOperation: $activeOperation)';
  }
}

/// @nodoc
abstract mixin class _$EnvironmentStateCopyWith<$Res>
    implements $EnvironmentStateCopyWith<$Res> {
  factory _$EnvironmentStateCopyWith(
          _EnvironmentState value, $Res Function(_EnvironmentState) _then) =
      __$EnvironmentStateCopyWithImpl;
  @override
  @useResult
  $Res call(
      {List<EnvironmentInfo> environments, bool busy, String? activeOperation});
}

/// @nodoc
class __$EnvironmentStateCopyWithImpl<$Res>
    implements _$EnvironmentStateCopyWith<$Res> {
  __$EnvironmentStateCopyWithImpl(this._self, this._then);

  final _EnvironmentState _self;
  final $Res Function(_EnvironmentState) _then;

  /// Create a copy of EnvironmentState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? environments = null,
    Object? busy = null,
    Object? activeOperation = freezed,
  }) {
    return _then(_EnvironmentState(
      environments: null == environments
          ? _self._environments
          : environments // ignore: cast_nullable_to_non_nullable
              as List<EnvironmentInfo>,
      busy: null == busy
          ? _self.busy
          : busy // ignore: cast_nullable_to_non_nullable
              as bool,
      activeOperation: freezed == activeOperation
          ? _self.activeOperation
          : activeOperation // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

// dart format on
