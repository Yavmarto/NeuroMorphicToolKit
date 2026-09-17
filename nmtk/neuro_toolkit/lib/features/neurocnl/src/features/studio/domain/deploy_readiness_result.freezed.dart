// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'deploy_readiness_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
DeployReadinessResult _$DeployReadinessResultFromJson(
  Map<String, dynamic> json
) {
        switch (json['status']) {
                  case 'unsupported':
          return DeployReadinessUnsupported.fromJson(
            json
          );
                case 'error':
          return DeployReadinessError.fromJson(
            json
          );
        
          default:
            return DeployReadinessOk.fromJson(
  json
);
        }
      
}

/// @nodoc
mixin _$DeployReadinessResult {



  /// Serializes this DeployReadinessResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeployReadinessResult);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DeployReadinessResult()';
}


}

/// @nodoc
class $DeployReadinessResultCopyWith<$Res>  {
$DeployReadinessResultCopyWith(DeployReadinessResult _, $Res Function(DeployReadinessResult) __);
}


/// Adds pattern-matching-related methods to [DeployReadinessResult].
extension DeployReadinessResultPatterns on DeployReadinessResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DeployReadinessOk value)?  ok,TResult Function( DeployReadinessUnsupported value)?  unsupported,TResult Function( DeployReadinessError value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DeployReadinessOk() when ok != null:
return ok(_that);case DeployReadinessUnsupported() when unsupported != null:
return unsupported(_that);case DeployReadinessError() when error != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DeployReadinessOk value)  ok,required TResult Function( DeployReadinessUnsupported value)  unsupported,required TResult Function( DeployReadinessError value)  error,}){
final _that = this;
switch (_that) {
case DeployReadinessOk():
return ok(_that);case DeployReadinessUnsupported():
return unsupported(_that);case DeployReadinessError():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DeployReadinessOk value)?  ok,TResult? Function( DeployReadinessUnsupported value)?  unsupported,TResult? Function( DeployReadinessError value)?  error,}){
final _that = this;
switch (_that) {
case DeployReadinessOk() when ok != null:
return ok(_that);case DeployReadinessUnsupported() when unsupported != null:
return unsupported(_that);case DeployReadinessError() when error != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  ok,TResult Function( String level,  List<String> unsupportedNodes,  List<String> diagnostics)?  unsupported,TResult Function( String message)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DeployReadinessOk() when ok != null:
return ok();case DeployReadinessUnsupported() when unsupported != null:
return unsupported(_that.level,_that.unsupportedNodes,_that.diagnostics);case DeployReadinessError() when error != null:
return error(_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  ok,required TResult Function( String level,  List<String> unsupportedNodes,  List<String> diagnostics)  unsupported,required TResult Function( String message)  error,}) {final _that = this;
switch (_that) {
case DeployReadinessOk():
return ok();case DeployReadinessUnsupported():
return unsupported(_that.level,_that.unsupportedNodes,_that.diagnostics);case DeployReadinessError():
return error(_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  ok,TResult? Function( String level,  List<String> unsupportedNodes,  List<String> diagnostics)?  unsupported,TResult? Function( String message)?  error,}) {final _that = this;
switch (_that) {
case DeployReadinessOk() when ok != null:
return ok();case DeployReadinessUnsupported() when unsupported != null:
return unsupported(_that.level,_that.unsupportedNodes,_that.diagnostics);case DeployReadinessError() when error != null:
return error(_that.message);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class DeployReadinessOk extends DeployReadinessResult {
  const DeployReadinessOk({final  String? $type}): $type = $type ?? 'ok',super._();
  factory DeployReadinessOk.fromJson(Map<String, dynamic> json) => _$DeployReadinessOkFromJson(json);



@JsonKey(name: 'status')
final String $type;



@override
Map<String, dynamic> toJson() {
  return _$DeployReadinessOkToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeployReadinessOk);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DeployReadinessResult.ok()';
}


}




/// @nodoc
@JsonSerializable()

class DeployReadinessUnsupported extends DeployReadinessResult {
  const DeployReadinessUnsupported({required this.level, required final  List<String> unsupportedNodes, required final  List<String> diagnostics, final  String? $type}): _unsupportedNodes = unsupportedNodes,_diagnostics = diagnostics,$type = $type ?? 'unsupported',super._();
  factory DeployReadinessUnsupported.fromJson(Map<String, dynamic> json) => _$DeployReadinessUnsupportedFromJson(json);

 final  String level;
// 'approximate' | 'unsupported'
 final  List<String> _unsupportedNodes;
// 'approximate' | 'unsupported'
 List<String> get unsupportedNodes {
  if (_unsupportedNodes is EqualUnmodifiableListView) return _unsupportedNodes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_unsupportedNodes);
}

 final  List<String> _diagnostics;
 List<String> get diagnostics {
  if (_diagnostics is EqualUnmodifiableListView) return _diagnostics;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_diagnostics);
}


@JsonKey(name: 'status')
final String $type;


/// Create a copy of DeployReadinessResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeployReadinessUnsupportedCopyWith<DeployReadinessUnsupported> get copyWith => _$DeployReadinessUnsupportedCopyWithImpl<DeployReadinessUnsupported>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DeployReadinessUnsupportedToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeployReadinessUnsupported&&(identical(other.level, level) || other.level == level)&&const DeepCollectionEquality().equals(other._unsupportedNodes, _unsupportedNodes)&&const DeepCollectionEquality().equals(other._diagnostics, _diagnostics));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,level,const DeepCollectionEquality().hash(_unsupportedNodes),const DeepCollectionEquality().hash(_diagnostics));

@override
String toString() {
  return 'DeployReadinessResult.unsupported(level: $level, unsupportedNodes: $unsupportedNodes, diagnostics: $diagnostics)';
}


}

/// @nodoc
abstract mixin class $DeployReadinessUnsupportedCopyWith<$Res> implements $DeployReadinessResultCopyWith<$Res> {
  factory $DeployReadinessUnsupportedCopyWith(DeployReadinessUnsupported value, $Res Function(DeployReadinessUnsupported) _then) = _$DeployReadinessUnsupportedCopyWithImpl;
@useResult
$Res call({
 String level, List<String> unsupportedNodes, List<String> diagnostics
});




}
/// @nodoc
class _$DeployReadinessUnsupportedCopyWithImpl<$Res>
    implements $DeployReadinessUnsupportedCopyWith<$Res> {
  _$DeployReadinessUnsupportedCopyWithImpl(this._self, this._then);

  final DeployReadinessUnsupported _self;
  final $Res Function(DeployReadinessUnsupported) _then;

/// Create a copy of DeployReadinessResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? level = null,Object? unsupportedNodes = null,Object? diagnostics = null,}) {
  return _then(DeployReadinessUnsupported(
level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,unsupportedNodes: null == unsupportedNodes ? _self._unsupportedNodes : unsupportedNodes // ignore: cast_nullable_to_non_nullable
as List<String>,diagnostics: null == diagnostics ? _self._diagnostics : diagnostics // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc
@JsonSerializable()

class DeployReadinessError extends DeployReadinessResult {
  const DeployReadinessError({required this.message, final  String? $type}): $type = $type ?? 'error',super._();
  factory DeployReadinessError.fromJson(Map<String, dynamic> json) => _$DeployReadinessErrorFromJson(json);

 final  String message;

@JsonKey(name: 'status')
final String $type;


/// Create a copy of DeployReadinessResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeployReadinessErrorCopyWith<DeployReadinessError> get copyWith => _$DeployReadinessErrorCopyWithImpl<DeployReadinessError>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DeployReadinessErrorToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeployReadinessError&&(identical(other.message, message) || other.message == message));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'DeployReadinessResult.error(message: $message)';
}


}

/// @nodoc
abstract mixin class $DeployReadinessErrorCopyWith<$Res> implements $DeployReadinessResultCopyWith<$Res> {
  factory $DeployReadinessErrorCopyWith(DeployReadinessError value, $Res Function(DeployReadinessError) _then) = _$DeployReadinessErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$DeployReadinessErrorCopyWithImpl<$Res>
    implements $DeployReadinessErrorCopyWith<$Res> {
  _$DeployReadinessErrorCopyWithImpl(this._self, this._then);

  final DeployReadinessError _self;
  final $Res Function(DeployReadinessError) _then;

/// Create a copy of DeployReadinessResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(DeployReadinessError(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
