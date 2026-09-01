// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'simulator_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SimulatorRunState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SimulatorRunState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SimulatorRunState()';
}


}

/// @nodoc
class $SimulatorRunStateCopyWith<$Res>  {
$SimulatorRunStateCopyWith(SimulatorRunState _, $Res Function(SimulatorRunState) __);
}


/// Adds pattern-matching-related methods to [SimulatorRunState].
extension SimulatorRunStatePatterns on SimulatorRunState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SimulatorRunIdle value)?  idle,TResult Function( SimulatorRunLoading value)?  loading,TResult Function( SimulatorRunSuccess value)?  success,TResult Function( SimulatorRunError value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SimulatorRunIdle() when idle != null:
return idle(_that);case SimulatorRunLoading() when loading != null:
return loading(_that);case SimulatorRunSuccess() when success != null:
return success(_that);case SimulatorRunError() when error != null:
return error(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SimulatorRunIdle value)  idle,required TResult Function( SimulatorRunLoading value)  loading,required TResult Function( SimulatorRunSuccess value)  success,required TResult Function( SimulatorRunError value)  error,}){
final _that = this;
switch (_that) {
case SimulatorRunIdle():
return idle(_that);case SimulatorRunLoading():
return loading(_that);case SimulatorRunSuccess():
return success(_that);case SimulatorRunError():
return error(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SimulatorRunIdle value)?  idle,TResult? Function( SimulatorRunLoading value)?  loading,TResult? Function( SimulatorRunSuccess value)?  success,TResult? Function( SimulatorRunError value)?  error,}){
final _that = this;
switch (_that) {
case SimulatorRunIdle() when idle != null:
return idle(_that);case SimulatorRunLoading() when loading != null:
return loading(_that);case SimulatorRunSuccess() when success != null:
return success(_that);case SimulatorRunError() when error != null:
return error(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function()?  loading,TResult Function( SimulatorRunResult result)?  success,TResult Function( String message,  List<String> details,  int? statusCode)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SimulatorRunIdle() when idle != null:
return idle();case SimulatorRunLoading() when loading != null:
return loading();case SimulatorRunSuccess() when success != null:
return success(_that.result);case SimulatorRunError() when error != null:
return error(_that.message,_that.details,_that.statusCode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function()  loading,required TResult Function( SimulatorRunResult result)  success,required TResult Function( String message,  List<String> details,  int? statusCode)  error,}) {final _that = this;
switch (_that) {
case SimulatorRunIdle():
return idle();case SimulatorRunLoading():
return loading();case SimulatorRunSuccess():
return success(_that.result);case SimulatorRunError():
return error(_that.message,_that.details,_that.statusCode);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function()?  loading,TResult? Function( SimulatorRunResult result)?  success,TResult? Function( String message,  List<String> details,  int? statusCode)?  error,}) {final _that = this;
switch (_that) {
case SimulatorRunIdle() when idle != null:
return idle();case SimulatorRunLoading() when loading != null:
return loading();case SimulatorRunSuccess() when success != null:
return success(_that.result);case SimulatorRunError() when error != null:
return error(_that.message,_that.details,_that.statusCode);case _:
  return null;

}
}

}

/// @nodoc


class SimulatorRunIdle implements SimulatorRunState {
  const SimulatorRunIdle();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SimulatorRunIdle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SimulatorRunState.idle()';
}


}




/// @nodoc


class SimulatorRunLoading implements SimulatorRunState {
  const SimulatorRunLoading();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SimulatorRunLoading);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SimulatorRunState.loading()';
}


}




/// @nodoc


class SimulatorRunSuccess implements SimulatorRunState {
  const SimulatorRunSuccess(this.result);


 final  SimulatorRunResult result;

/// Create a copy of SimulatorRunState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SimulatorRunSuccessCopyWith<SimulatorRunSuccess> get copyWith => _$SimulatorRunSuccessCopyWithImpl<SimulatorRunSuccess>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SimulatorRunSuccess&&(identical(other.result, result) || other.result == result));
}


@override
int get hashCode => Object.hash(runtimeType,result);

@override
String toString() {
  return 'SimulatorRunState.success(result: $result)';
}


}

/// @nodoc
abstract mixin class $SimulatorRunSuccessCopyWith<$Res> implements $SimulatorRunStateCopyWith<$Res> {
  factory $SimulatorRunSuccessCopyWith(SimulatorRunSuccess value, $Res Function(SimulatorRunSuccess) _then) = _$SimulatorRunSuccessCopyWithImpl;
@useResult
$Res call({
 SimulatorRunResult result
});




}
/// @nodoc
class _$SimulatorRunSuccessCopyWithImpl<$Res>
    implements $SimulatorRunSuccessCopyWith<$Res> {
  _$SimulatorRunSuccessCopyWithImpl(this._self, this._then);

  final SimulatorRunSuccess _self;
  final $Res Function(SimulatorRunSuccess) _then;

/// Create a copy of SimulatorRunState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? result = null,}) {
  return _then(SimulatorRunSuccess(
null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as SimulatorRunResult,
  ));
}


}

/// @nodoc


class SimulatorRunError implements SimulatorRunState {
  const SimulatorRunError(this.message, {final  List<String> details = const [], this.statusCode}): _details = details;


 final  String message;
 final  List<String> _details;
@JsonKey() List<String> get details {
  if (_details is EqualUnmodifiableListView) return _details;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_details);
}

 final  int? statusCode;

/// Create a copy of SimulatorRunState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SimulatorRunErrorCopyWith<SimulatorRunError> get copyWith => _$SimulatorRunErrorCopyWithImpl<SimulatorRunError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SimulatorRunError&&(identical(other.message, message) || other.message == message)&&const DeepCollectionEquality().equals(other._details, _details)&&(identical(other.statusCode, statusCode) || other.statusCode == statusCode));
}


@override
int get hashCode => Object.hash(runtimeType,message,const DeepCollectionEquality().hash(_details),statusCode);

@override
String toString() {
  return 'SimulatorRunState.error(message: $message, details: $details, statusCode: $statusCode)';
}


}

/// @nodoc
abstract mixin class $SimulatorRunErrorCopyWith<$Res> implements $SimulatorRunStateCopyWith<$Res> {
  factory $SimulatorRunErrorCopyWith(SimulatorRunError value, $Res Function(SimulatorRunError) _then) = _$SimulatorRunErrorCopyWithImpl;
@useResult
$Res call({
 String message, List<String> details, int? statusCode
});




}
/// @nodoc
class _$SimulatorRunErrorCopyWithImpl<$Res>
    implements $SimulatorRunErrorCopyWith<$Res> {
  _$SimulatorRunErrorCopyWithImpl(this._self, this._then);

  final SimulatorRunError _self;
  final $Res Function(SimulatorRunError) _then;

/// Create a copy of SimulatorRunState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,Object? details = null,Object? statusCode = freezed,}) {
  return _then(SimulatorRunError(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,details: null == details ? _self._details : details // ignore: cast_nullable_to_non_nullable
as List<String>,statusCode: freezed == statusCode ? _self.statusCode : statusCode // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
