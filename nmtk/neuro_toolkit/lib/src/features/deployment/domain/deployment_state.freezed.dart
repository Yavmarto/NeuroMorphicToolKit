// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'deployment_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DeploymentState {
  List<DeploymentTarget> get targets;
  DeploymentJob? get activeJob;
  bool
      get isReady; // Set instead of silently clearing activeJob when the notifier loses
// contact with a running job (staleness watchdog / repeated poll
// failures) -- the UI must always show an honest reason rather than
// falling through to an unrelated stale card.
  String? get connectionLostReason;

  /// Create a copy of DeploymentState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $DeploymentStateCopyWith<DeploymentState> get copyWith =>
      _$DeploymentStateCopyWithImpl<DeploymentState>(
          this as DeploymentState, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is DeploymentState &&
            const DeepCollectionEquality().equals(other.targets, targets) &&
            (identical(other.activeJob, activeJob) ||
                other.activeJob == activeJob) &&
            (identical(other.isReady, isReady) || other.isReady == isReady) &&
            (identical(other.connectionLostReason, connectionLostReason) ||
                other.connectionLostReason == connectionLostReason));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(targets),
      activeJob,
      isReady,
      connectionLostReason);

  @override
  String toString() {
    return 'DeploymentState(targets: $targets, activeJob: $activeJob, isReady: $isReady, connectionLostReason: $connectionLostReason)';
  }
}

/// @nodoc
abstract mixin class $DeploymentStateCopyWith<$Res> {
  factory $DeploymentStateCopyWith(
          DeploymentState value, $Res Function(DeploymentState) _then) =
      _$DeploymentStateCopyWithImpl;
  @useResult
  $Res call(
      {List<DeploymentTarget> targets,
      DeploymentJob? activeJob,
      bool isReady,
      String? connectionLostReason});
}

/// @nodoc
class _$DeploymentStateCopyWithImpl<$Res>
    implements $DeploymentStateCopyWith<$Res> {
  _$DeploymentStateCopyWithImpl(this._self, this._then);

  final DeploymentState _self;
  final $Res Function(DeploymentState) _then;

  /// Create a copy of DeploymentState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? targets = null,
    Object? activeJob = freezed,
    Object? isReady = null,
    Object? connectionLostReason = freezed,
  }) {
    return _then(_self.copyWith(
      targets: null == targets
          ? _self.targets
          : targets // ignore: cast_nullable_to_non_nullable
              as List<DeploymentTarget>,
      activeJob: freezed == activeJob
          ? _self.activeJob
          : activeJob // ignore: cast_nullable_to_non_nullable
              as DeploymentJob?,
      isReady: null == isReady
          ? _self.isReady
          : isReady // ignore: cast_nullable_to_non_nullable
              as bool,
      connectionLostReason: freezed == connectionLostReason
          ? _self.connectionLostReason
          : connectionLostReason // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [DeploymentState].
extension DeploymentStatePatterns on DeploymentState {
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
    TResult Function(_DeploymentState value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _DeploymentState() when $default != null:
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
    TResult Function(_DeploymentState value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DeploymentState():
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
    TResult? Function(_DeploymentState value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DeploymentState() when $default != null:
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
    TResult Function(List<DeploymentTarget> targets, DeploymentJob? activeJob,
            bool isReady, String? connectionLostReason)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _DeploymentState() when $default != null:
        return $default(_that.targets, _that.activeJob, _that.isReady,
            _that.connectionLostReason);
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
    TResult Function(List<DeploymentTarget> targets, DeploymentJob? activeJob,
            bool isReady, String? connectionLostReason)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DeploymentState():
        return $default(_that.targets, _that.activeJob, _that.isReady,
            _that.connectionLostReason);
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
    TResult? Function(List<DeploymentTarget> targets, DeploymentJob? activeJob,
            bool isReady, String? connectionLostReason)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DeploymentState() when $default != null:
        return $default(_that.targets, _that.activeJob, _that.isReady,
            _that.connectionLostReason);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _DeploymentState implements DeploymentState {
  const _DeploymentState(
      {final List<DeploymentTarget> targets = const [],
      this.activeJob,
      this.isReady = false,
      this.connectionLostReason})
      : _targets = targets;

  final List<DeploymentTarget> _targets;
  @override
  @JsonKey()
  List<DeploymentTarget> get targets {
    if (_targets is EqualUnmodifiableListView) return _targets;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_targets);
  }

  @override
  final DeploymentJob? activeJob;
  @override
  @JsonKey()
  final bool isReady;
// Set instead of silently clearing activeJob when the notifier loses
// contact with a running job (staleness watchdog / repeated poll
// failures) -- the UI must always show an honest reason rather than
// falling through to an unrelated stale card.
  @override
  final String? connectionLostReason;

  /// Create a copy of DeploymentState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$DeploymentStateCopyWith<_DeploymentState> get copyWith =>
      __$DeploymentStateCopyWithImpl<_DeploymentState>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _DeploymentState &&
            const DeepCollectionEquality().equals(other._targets, _targets) &&
            (identical(other.activeJob, activeJob) ||
                other.activeJob == activeJob) &&
            (identical(other.isReady, isReady) || other.isReady == isReady) &&
            (identical(other.connectionLostReason, connectionLostReason) ||
                other.connectionLostReason == connectionLostReason));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_targets),
      activeJob,
      isReady,
      connectionLostReason);

  @override
  String toString() {
    return 'DeploymentState(targets: $targets, activeJob: $activeJob, isReady: $isReady, connectionLostReason: $connectionLostReason)';
  }
}

/// @nodoc
abstract mixin class _$DeploymentStateCopyWith<$Res>
    implements $DeploymentStateCopyWith<$Res> {
  factory _$DeploymentStateCopyWith(
          _DeploymentState value, $Res Function(_DeploymentState) _then) =
      __$DeploymentStateCopyWithImpl;
  @override
  @useResult
  $Res call(
      {List<DeploymentTarget> targets,
      DeploymentJob? activeJob,
      bool isReady,
      String? connectionLostReason});
}

/// @nodoc
class __$DeploymentStateCopyWithImpl<$Res>
    implements _$DeploymentStateCopyWith<$Res> {
  __$DeploymentStateCopyWithImpl(this._self, this._then);

  final _DeploymentState _self;
  final $Res Function(_DeploymentState) _then;

  /// Create a copy of DeploymentState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? targets = null,
    Object? activeJob = freezed,
    Object? isReady = null,
    Object? connectionLostReason = freezed,
  }) {
    return _then(_DeploymentState(
      targets: null == targets
          ? _self._targets
          : targets // ignore: cast_nullable_to_non_nullable
              as List<DeploymentTarget>,
      activeJob: freezed == activeJob
          ? _self.activeJob
          : activeJob // ignore: cast_nullable_to_non_nullable
              as DeploymentJob?,
      isReady: null == isReady
          ? _self.isReady
          : isReady // ignore: cast_nullable_to_non_nullable
              as bool,
      connectionLostReason: freezed == connectionLostReason
          ? _self.connectionLostReason
          : connectionLostReason // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

// dart format on
