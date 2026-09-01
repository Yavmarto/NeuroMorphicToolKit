// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'workspace_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$WorkspaceState {

 List<WorkspaceSession> get sessions; String? get focusedModuleId; bool get defaultSessionsEnsured;
/// Create a copy of WorkspaceState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceStateCopyWith<WorkspaceState> get copyWith => _$WorkspaceStateCopyWithImpl<WorkspaceState>(this as WorkspaceState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceState&&const DeepCollectionEquality().equals(other.sessions, sessions)&&(identical(other.focusedModuleId, focusedModuleId) || other.focusedModuleId == focusedModuleId)&&(identical(other.defaultSessionsEnsured, defaultSessionsEnsured) || other.defaultSessionsEnsured == defaultSessionsEnsured));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(sessions),focusedModuleId,defaultSessionsEnsured);

@override
String toString() {
  return 'WorkspaceState(sessions: $sessions, focusedModuleId: $focusedModuleId, defaultSessionsEnsured: $defaultSessionsEnsured)';
}


}

/// @nodoc
abstract mixin class $WorkspaceStateCopyWith<$Res>  {
  factory $WorkspaceStateCopyWith(WorkspaceState value, $Res Function(WorkspaceState) _then) = _$WorkspaceStateCopyWithImpl;
@useResult
$Res call({
 List<WorkspaceSession> sessions, String? focusedModuleId, bool defaultSessionsEnsured
});




}
/// @nodoc
class _$WorkspaceStateCopyWithImpl<$Res>
    implements $WorkspaceStateCopyWith<$Res> {
  _$WorkspaceStateCopyWithImpl(this._self, this._then);

  final WorkspaceState _self;
  final $Res Function(WorkspaceState) _then;

/// Create a copy of WorkspaceState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessions = null,Object? focusedModuleId = freezed,Object? defaultSessionsEnsured = null,}) {
  return _then(_self.copyWith(
sessions: null == sessions ? _self.sessions : sessions // ignore: cast_nullable_to_non_nullable
as List<WorkspaceSession>,focusedModuleId: freezed == focusedModuleId ? _self.focusedModuleId : focusedModuleId // ignore: cast_nullable_to_non_nullable
as String?,defaultSessionsEnsured: null == defaultSessionsEnsured ? _self.defaultSessionsEnsured : defaultSessionsEnsured // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkspaceState].
extension WorkspaceStatePatterns on WorkspaceState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkspaceState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkspaceState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkspaceState value)  $default,){
final _that = this;
switch (_that) {
case _WorkspaceState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkspaceState value)?  $default,){
final _that = this;
switch (_that) {
case _WorkspaceState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<WorkspaceSession> sessions,  String? focusedModuleId,  bool defaultSessionsEnsured)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkspaceState() when $default != null:
return $default(_that.sessions,_that.focusedModuleId,_that.defaultSessionsEnsured);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<WorkspaceSession> sessions,  String? focusedModuleId,  bool defaultSessionsEnsured)  $default,) {final _that = this;
switch (_that) {
case _WorkspaceState():
return $default(_that.sessions,_that.focusedModuleId,_that.defaultSessionsEnsured);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<WorkspaceSession> sessions,  String? focusedModuleId,  bool defaultSessionsEnsured)?  $default,) {final _that = this;
switch (_that) {
case _WorkspaceState() when $default != null:
return $default(_that.sessions,_that.focusedModuleId,_that.defaultSessionsEnsured);case _:
  return null;

}
}

}

/// @nodoc


class _WorkspaceState extends WorkspaceState {
  const _WorkspaceState({final  List<WorkspaceSession> sessions = const [], this.focusedModuleId, this.defaultSessionsEnsured = false}): _sessions = sessions,super._();


 final  List<WorkspaceSession> _sessions;
@override@JsonKey() List<WorkspaceSession> get sessions {
  if (_sessions is EqualUnmodifiableListView) return _sessions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_sessions);
}

@override final  String? focusedModuleId;
@override@JsonKey() final  bool defaultSessionsEnsured;

/// Create a copy of WorkspaceState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkspaceStateCopyWith<_WorkspaceState> get copyWith => __$WorkspaceStateCopyWithImpl<_WorkspaceState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkspaceState&&const DeepCollectionEquality().equals(other._sessions, _sessions)&&(identical(other.focusedModuleId, focusedModuleId) || other.focusedModuleId == focusedModuleId)&&(identical(other.defaultSessionsEnsured, defaultSessionsEnsured) || other.defaultSessionsEnsured == defaultSessionsEnsured));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_sessions),focusedModuleId,defaultSessionsEnsured);

@override
String toString() {
  return 'WorkspaceState(sessions: $sessions, focusedModuleId: $focusedModuleId, defaultSessionsEnsured: $defaultSessionsEnsured)';
}


}

/// @nodoc
abstract mixin class _$WorkspaceStateCopyWith<$Res> implements $WorkspaceStateCopyWith<$Res> {
  factory _$WorkspaceStateCopyWith(_WorkspaceState value, $Res Function(_WorkspaceState) _then) = __$WorkspaceStateCopyWithImpl;
@override @useResult
$Res call({
 List<WorkspaceSession> sessions, String? focusedModuleId, bool defaultSessionsEnsured
});




}
/// @nodoc
class __$WorkspaceStateCopyWithImpl<$Res>
    implements _$WorkspaceStateCopyWith<$Res> {
  __$WorkspaceStateCopyWithImpl(this._self, this._then);

  final _WorkspaceState _self;
  final $Res Function(_WorkspaceState) _then;

/// Create a copy of WorkspaceState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessions = null,Object? focusedModuleId = freezed,Object? defaultSessionsEnsured = null,}) {
  return _then(_WorkspaceState(
sessions: null == sessions ? _self._sessions : sessions // ignore: cast_nullable_to_non_nullable
as List<WorkspaceSession>,focusedModuleId: freezed == focusedModuleId ? _self.focusedModuleId : focusedModuleId // ignore: cast_nullable_to_non_nullable
as String?,defaultSessionsEnsured: null == defaultSessionsEnsured ? _self.defaultSessionsEnsured : defaultSessionsEnsured // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
