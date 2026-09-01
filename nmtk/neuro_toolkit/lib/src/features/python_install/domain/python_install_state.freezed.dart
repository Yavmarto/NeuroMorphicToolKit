// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'python_install_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PythonInstallState {

 bool get isInstalling; bool get isChecking; String? get installOutput; String? get errorMessage;
/// Create a copy of PythonInstallState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PythonInstallStateCopyWith<PythonInstallState> get copyWith => _$PythonInstallStateCopyWithImpl<PythonInstallState>(this as PythonInstallState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PythonInstallState&&(identical(other.isInstalling, isInstalling) || other.isInstalling == isInstalling)&&(identical(other.isChecking, isChecking) || other.isChecking == isChecking)&&(identical(other.installOutput, installOutput) || other.installOutput == installOutput)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode => Object.hash(runtimeType,isInstalling,isChecking,installOutput,errorMessage);

@override
String toString() {
  return 'PythonInstallState(isInstalling: $isInstalling, isChecking: $isChecking, installOutput: $installOutput, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class $PythonInstallStateCopyWith<$Res>  {
  factory $PythonInstallStateCopyWith(PythonInstallState value, $Res Function(PythonInstallState) _then) = _$PythonInstallStateCopyWithImpl;
@useResult
$Res call({
 bool isInstalling, bool isChecking, String? installOutput, String? errorMessage
});




}
/// @nodoc
class _$PythonInstallStateCopyWithImpl<$Res>
    implements $PythonInstallStateCopyWith<$Res> {
  _$PythonInstallStateCopyWithImpl(this._self, this._then);

  final PythonInstallState _self;
  final $Res Function(PythonInstallState) _then;

/// Create a copy of PythonInstallState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? isInstalling = null,Object? isChecking = null,Object? installOutput = freezed,Object? errorMessage = freezed,}) {
  return _then(_self.copyWith(
isInstalling: null == isInstalling ? _self.isInstalling : isInstalling // ignore: cast_nullable_to_non_nullable
as bool,isChecking: null == isChecking ? _self.isChecking : isChecking // ignore: cast_nullable_to_non_nullable
as bool,installOutput: freezed == installOutput ? _self.installOutput : installOutput // ignore: cast_nullable_to_non_nullable
as String?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [PythonInstallState].
extension PythonInstallStatePatterns on PythonInstallState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PythonInstallState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PythonInstallState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PythonInstallState value)  $default,){
final _that = this;
switch (_that) {
case _PythonInstallState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PythonInstallState value)?  $default,){
final _that = this;
switch (_that) {
case _PythonInstallState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool isInstalling,  bool isChecking,  String? installOutput,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PythonInstallState() when $default != null:
return $default(_that.isInstalling,_that.isChecking,_that.installOutput,_that.errorMessage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool isInstalling,  bool isChecking,  String? installOutput,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _PythonInstallState():
return $default(_that.isInstalling,_that.isChecking,_that.installOutput,_that.errorMessage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool isInstalling,  bool isChecking,  String? installOutput,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _PythonInstallState() when $default != null:
return $default(_that.isInstalling,_that.isChecking,_that.installOutput,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc


class _PythonInstallState implements PythonInstallState {
  const _PythonInstallState({this.isInstalling = false, this.isChecking = false, this.installOutput, this.errorMessage});


@override@JsonKey() final  bool isInstalling;
@override@JsonKey() final  bool isChecking;
@override final  String? installOutput;
@override final  String? errorMessage;

/// Create a copy of PythonInstallState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PythonInstallStateCopyWith<_PythonInstallState> get copyWith => __$PythonInstallStateCopyWithImpl<_PythonInstallState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PythonInstallState&&(identical(other.isInstalling, isInstalling) || other.isInstalling == isInstalling)&&(identical(other.isChecking, isChecking) || other.isChecking == isChecking)&&(identical(other.installOutput, installOutput) || other.installOutput == installOutput)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode => Object.hash(runtimeType,isInstalling,isChecking,installOutput,errorMessage);

@override
String toString() {
  return 'PythonInstallState(isInstalling: $isInstalling, isChecking: $isChecking, installOutput: $installOutput, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$PythonInstallStateCopyWith<$Res> implements $PythonInstallStateCopyWith<$Res> {
  factory _$PythonInstallStateCopyWith(_PythonInstallState value, $Res Function(_PythonInstallState) _then) = __$PythonInstallStateCopyWithImpl;
@override @useResult
$Res call({
 bool isInstalling, bool isChecking, String? installOutput, String? errorMessage
});




}
/// @nodoc
class __$PythonInstallStateCopyWithImpl<$Res>
    implements _$PythonInstallStateCopyWith<$Res> {
  __$PythonInstallStateCopyWithImpl(this._self, this._then);

  final _PythonInstallState _self;
  final $Res Function(_PythonInstallState) _then;

/// Create a copy of PythonInstallState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? isInstalling = null,Object? isChecking = null,Object? installOutput = freezed,Object? errorMessage = freezed,}) {
  return _then(_PythonInstallState(
isInstalling: null == isInstalling ? _self.isInstalling : isInstalling // ignore: cast_nullable_to_non_nullable
as bool,isChecking: null == isChecking ? _self.isChecking : isChecking // ignore: cast_nullable_to_non_nullable
as bool,installOutput: freezed == installOutput ? _self.installOutput : installOutput // ignore: cast_nullable_to_non_nullable
as String?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
