// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'pipeline_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PipelineState {

 StepStatus get parseStatus; StepStatus get validateStatus; StepStatus get generateStatus; StepStatus get simulateStatus; StepStatus get deployReadinessStatus; ParseResult? get parseResult; ValidationResult? get validateResult; GenerateResult? get generateResult; SimulationResult? get simulateResult; DeployReadinessResult? get deployReadinessResult; String? get errorMessage;/// When preview generation is running, tracks start time and requested duration.
 DateTime? get simulationStartTime; double? get requestedDuration;
/// Create a copy of PipelineState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PipelineStateCopyWith<PipelineState> get copyWith => _$PipelineStateCopyWithImpl<PipelineState>(this as PipelineState, _$identity);

  /// Serializes this PipelineState to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PipelineState&&(identical(other.parseStatus, parseStatus) || other.parseStatus == parseStatus)&&(identical(other.validateStatus, validateStatus) || other.validateStatus == validateStatus)&&(identical(other.generateStatus, generateStatus) || other.generateStatus == generateStatus)&&(identical(other.simulateStatus, simulateStatus) || other.simulateStatus == simulateStatus)&&(identical(other.deployReadinessStatus, deployReadinessStatus) || other.deployReadinessStatus == deployReadinessStatus)&&(identical(other.parseResult, parseResult) || other.parseResult == parseResult)&&(identical(other.validateResult, validateResult) || other.validateResult == validateResult)&&(identical(other.generateResult, generateResult) || other.generateResult == generateResult)&&(identical(other.simulateResult, simulateResult) || other.simulateResult == simulateResult)&&(identical(other.deployReadinessResult, deployReadinessResult) || other.deployReadinessResult == deployReadinessResult)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&(identical(other.simulationStartTime, simulationStartTime) || other.simulationStartTime == simulationStartTime)&&(identical(other.requestedDuration, requestedDuration) || other.requestedDuration == requestedDuration));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,parseStatus,validateStatus,generateStatus,simulateStatus,deployReadinessStatus,parseResult,validateResult,generateResult,simulateResult,deployReadinessResult,errorMessage,simulationStartTime,requestedDuration);

@override
String toString() {
  return 'PipelineState(parseStatus: $parseStatus, validateStatus: $validateStatus, generateStatus: $generateStatus, simulateStatus: $simulateStatus, deployReadinessStatus: $deployReadinessStatus, parseResult: $parseResult, validateResult: $validateResult, generateResult: $generateResult, simulateResult: $simulateResult, deployReadinessResult: $deployReadinessResult, errorMessage: $errorMessage, simulationStartTime: $simulationStartTime, requestedDuration: $requestedDuration)';
}


}

/// @nodoc
abstract mixin class $PipelineStateCopyWith<$Res>  {
  factory $PipelineStateCopyWith(PipelineState value, $Res Function(PipelineState) _then) = _$PipelineStateCopyWithImpl;
@useResult
$Res call({
 StepStatus parseStatus, StepStatus validateStatus, StepStatus generateStatus, StepStatus simulateStatus, StepStatus deployReadinessStatus, ParseResult? parseResult, ValidationResult? validateResult, GenerateResult? generateResult, SimulationResult? simulateResult, DeployReadinessResult? deployReadinessResult, String? errorMessage, DateTime? simulationStartTime, double? requestedDuration
});


$DeployReadinessResultCopyWith<$Res>? get deployReadinessResult;

}
/// @nodoc
class _$PipelineStateCopyWithImpl<$Res>
    implements $PipelineStateCopyWith<$Res> {
  _$PipelineStateCopyWithImpl(this._self, this._then);

  final PipelineState _self;
  final $Res Function(PipelineState) _then;

/// Create a copy of PipelineState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? parseStatus = null,Object? validateStatus = null,Object? generateStatus = null,Object? simulateStatus = null,Object? deployReadinessStatus = null,Object? parseResult = freezed,Object? validateResult = freezed,Object? generateResult = freezed,Object? simulateResult = freezed,Object? deployReadinessResult = freezed,Object? errorMessage = freezed,Object? simulationStartTime = freezed,Object? requestedDuration = freezed,}) {
  return _then(_self.copyWith(
parseStatus: null == parseStatus ? _self.parseStatus : parseStatus // ignore: cast_nullable_to_non_nullable
as StepStatus,validateStatus: null == validateStatus ? _self.validateStatus : validateStatus // ignore: cast_nullable_to_non_nullable
as StepStatus,generateStatus: null == generateStatus ? _self.generateStatus : generateStatus // ignore: cast_nullable_to_non_nullable
as StepStatus,simulateStatus: null == simulateStatus ? _self.simulateStatus : simulateStatus // ignore: cast_nullable_to_non_nullable
as StepStatus,deployReadinessStatus: null == deployReadinessStatus ? _self.deployReadinessStatus : deployReadinessStatus // ignore: cast_nullable_to_non_nullable
as StepStatus,parseResult: freezed == parseResult ? _self.parseResult : parseResult // ignore: cast_nullable_to_non_nullable
as ParseResult?,validateResult: freezed == validateResult ? _self.validateResult : validateResult // ignore: cast_nullable_to_non_nullable
as ValidationResult?,generateResult: freezed == generateResult ? _self.generateResult : generateResult // ignore: cast_nullable_to_non_nullable
as GenerateResult?,simulateResult: freezed == simulateResult ? _self.simulateResult : simulateResult // ignore: cast_nullable_to_non_nullable
as SimulationResult?,deployReadinessResult: freezed == deployReadinessResult ? _self.deployReadinessResult : deployReadinessResult // ignore: cast_nullable_to_non_nullable
as DeployReadinessResult?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,simulationStartTime: freezed == simulationStartTime ? _self.simulationStartTime : simulationStartTime // ignore: cast_nullable_to_non_nullable
as DateTime?,requestedDuration: freezed == requestedDuration ? _self.requestedDuration : requestedDuration // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}
/// Create a copy of PipelineState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeployReadinessResultCopyWith<$Res>? get deployReadinessResult {
    if (_self.deployReadinessResult == null) {
    return null;
  }

  return $DeployReadinessResultCopyWith<$Res>(_self.deployReadinessResult!, (value) {
    return _then(_self.copyWith(deployReadinessResult: value));
  });
}
}


/// Adds pattern-matching-related methods to [PipelineState].
extension PipelineStatePatterns on PipelineState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PipelineState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PipelineState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PipelineState value)  $default,){
final _that = this;
switch (_that) {
case _PipelineState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PipelineState value)?  $default,){
final _that = this;
switch (_that) {
case _PipelineState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( StepStatus parseStatus,  StepStatus validateStatus,  StepStatus generateStatus,  StepStatus simulateStatus,  StepStatus deployReadinessStatus,  ParseResult? parseResult,  ValidationResult? validateResult,  GenerateResult? generateResult,  SimulationResult? simulateResult,  DeployReadinessResult? deployReadinessResult,  String? errorMessage,  DateTime? simulationStartTime,  double? requestedDuration)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PipelineState() when $default != null:
return $default(_that.parseStatus,_that.validateStatus,_that.generateStatus,_that.simulateStatus,_that.deployReadinessStatus,_that.parseResult,_that.validateResult,_that.generateResult,_that.simulateResult,_that.deployReadinessResult,_that.errorMessage,_that.simulationStartTime,_that.requestedDuration);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( StepStatus parseStatus,  StepStatus validateStatus,  StepStatus generateStatus,  StepStatus simulateStatus,  StepStatus deployReadinessStatus,  ParseResult? parseResult,  ValidationResult? validateResult,  GenerateResult? generateResult,  SimulationResult? simulateResult,  DeployReadinessResult? deployReadinessResult,  String? errorMessage,  DateTime? simulationStartTime,  double? requestedDuration)  $default,) {final _that = this;
switch (_that) {
case _PipelineState():
return $default(_that.parseStatus,_that.validateStatus,_that.generateStatus,_that.simulateStatus,_that.deployReadinessStatus,_that.parseResult,_that.validateResult,_that.generateResult,_that.simulateResult,_that.deployReadinessResult,_that.errorMessage,_that.simulationStartTime,_that.requestedDuration);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( StepStatus parseStatus,  StepStatus validateStatus,  StepStatus generateStatus,  StepStatus simulateStatus,  StepStatus deployReadinessStatus,  ParseResult? parseResult,  ValidationResult? validateResult,  GenerateResult? generateResult,  SimulationResult? simulateResult,  DeployReadinessResult? deployReadinessResult,  String? errorMessage,  DateTime? simulationStartTime,  double? requestedDuration)?  $default,) {final _that = this;
switch (_that) {
case _PipelineState() when $default != null:
return $default(_that.parseStatus,_that.validateStatus,_that.generateStatus,_that.simulateStatus,_that.deployReadinessStatus,_that.parseResult,_that.validateResult,_that.generateResult,_that.simulateResult,_that.deployReadinessResult,_that.errorMessage,_that.simulationStartTime,_that.requestedDuration);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PipelineState extends PipelineState {
  const _PipelineState({this.parseStatus = StepStatus.idle, this.validateStatus = StepStatus.idle, this.generateStatus = StepStatus.idle, this.simulateStatus = StepStatus.idle, this.deployReadinessStatus = StepStatus.idle, this.parseResult, this.validateResult, this.generateResult, this.simulateResult, this.deployReadinessResult, this.errorMessage, this.simulationStartTime, this.requestedDuration}): super._();
  factory _PipelineState.fromJson(Map<String, dynamic> json) => _$PipelineStateFromJson(json);

@override@JsonKey() final  StepStatus parseStatus;
@override@JsonKey() final  StepStatus validateStatus;
@override@JsonKey() final  StepStatus generateStatus;
@override@JsonKey() final  StepStatus simulateStatus;
@override@JsonKey() final  StepStatus deployReadinessStatus;
@override final  ParseResult? parseResult;
@override final  ValidationResult? validateResult;
@override final  GenerateResult? generateResult;
@override final  SimulationResult? simulateResult;
@override final  DeployReadinessResult? deployReadinessResult;
@override final  String? errorMessage;
/// When preview generation is running, tracks start time and requested duration.
@override final  DateTime? simulationStartTime;
@override final  double? requestedDuration;

/// Create a copy of PipelineState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PipelineStateCopyWith<_PipelineState> get copyWith => __$PipelineStateCopyWithImpl<_PipelineState>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PipelineStateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PipelineState&&(identical(other.parseStatus, parseStatus) || other.parseStatus == parseStatus)&&(identical(other.validateStatus, validateStatus) || other.validateStatus == validateStatus)&&(identical(other.generateStatus, generateStatus) || other.generateStatus == generateStatus)&&(identical(other.simulateStatus, simulateStatus) || other.simulateStatus == simulateStatus)&&(identical(other.deployReadinessStatus, deployReadinessStatus) || other.deployReadinessStatus == deployReadinessStatus)&&(identical(other.parseResult, parseResult) || other.parseResult == parseResult)&&(identical(other.validateResult, validateResult) || other.validateResult == validateResult)&&(identical(other.generateResult, generateResult) || other.generateResult == generateResult)&&(identical(other.simulateResult, simulateResult) || other.simulateResult == simulateResult)&&(identical(other.deployReadinessResult, deployReadinessResult) || other.deployReadinessResult == deployReadinessResult)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&(identical(other.simulationStartTime, simulationStartTime) || other.simulationStartTime == simulationStartTime)&&(identical(other.requestedDuration, requestedDuration) || other.requestedDuration == requestedDuration));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,parseStatus,validateStatus,generateStatus,simulateStatus,deployReadinessStatus,parseResult,validateResult,generateResult,simulateResult,deployReadinessResult,errorMessage,simulationStartTime,requestedDuration);

@override
String toString() {
  return 'PipelineState(parseStatus: $parseStatus, validateStatus: $validateStatus, generateStatus: $generateStatus, simulateStatus: $simulateStatus, deployReadinessStatus: $deployReadinessStatus, parseResult: $parseResult, validateResult: $validateResult, generateResult: $generateResult, simulateResult: $simulateResult, deployReadinessResult: $deployReadinessResult, errorMessage: $errorMessage, simulationStartTime: $simulationStartTime, requestedDuration: $requestedDuration)';
}


}

/// @nodoc
abstract mixin class _$PipelineStateCopyWith<$Res> implements $PipelineStateCopyWith<$Res> {
  factory _$PipelineStateCopyWith(_PipelineState value, $Res Function(_PipelineState) _then) = __$PipelineStateCopyWithImpl;
@override @useResult
$Res call({
 StepStatus parseStatus, StepStatus validateStatus, StepStatus generateStatus, StepStatus simulateStatus, StepStatus deployReadinessStatus, ParseResult? parseResult, ValidationResult? validateResult, GenerateResult? generateResult, SimulationResult? simulateResult, DeployReadinessResult? deployReadinessResult, String? errorMessage, DateTime? simulationStartTime, double? requestedDuration
});


@override $DeployReadinessResultCopyWith<$Res>? get deployReadinessResult;

}
/// @nodoc
class __$PipelineStateCopyWithImpl<$Res>
    implements _$PipelineStateCopyWith<$Res> {
  __$PipelineStateCopyWithImpl(this._self, this._then);

  final _PipelineState _self;
  final $Res Function(_PipelineState) _then;

/// Create a copy of PipelineState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? parseStatus = null,Object? validateStatus = null,Object? generateStatus = null,Object? simulateStatus = null,Object? deployReadinessStatus = null,Object? parseResult = freezed,Object? validateResult = freezed,Object? generateResult = freezed,Object? simulateResult = freezed,Object? deployReadinessResult = freezed,Object? errorMessage = freezed,Object? simulationStartTime = freezed,Object? requestedDuration = freezed,}) {
  return _then(_PipelineState(
parseStatus: null == parseStatus ? _self.parseStatus : parseStatus // ignore: cast_nullable_to_non_nullable
as StepStatus,validateStatus: null == validateStatus ? _self.validateStatus : validateStatus // ignore: cast_nullable_to_non_nullable
as StepStatus,generateStatus: null == generateStatus ? _self.generateStatus : generateStatus // ignore: cast_nullable_to_non_nullable
as StepStatus,simulateStatus: null == simulateStatus ? _self.simulateStatus : simulateStatus // ignore: cast_nullable_to_non_nullable
as StepStatus,deployReadinessStatus: null == deployReadinessStatus ? _self.deployReadinessStatus : deployReadinessStatus // ignore: cast_nullable_to_non_nullable
as StepStatus,parseResult: freezed == parseResult ? _self.parseResult : parseResult // ignore: cast_nullable_to_non_nullable
as ParseResult?,validateResult: freezed == validateResult ? _self.validateResult : validateResult // ignore: cast_nullable_to_non_nullable
as ValidationResult?,generateResult: freezed == generateResult ? _self.generateResult : generateResult // ignore: cast_nullable_to_non_nullable
as GenerateResult?,simulateResult: freezed == simulateResult ? _self.simulateResult : simulateResult // ignore: cast_nullable_to_non_nullable
as SimulationResult?,deployReadinessResult: freezed == deployReadinessResult ? _self.deployReadinessResult : deployReadinessResult // ignore: cast_nullable_to_non_nullable
as DeployReadinessResult?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,simulationStartTime: freezed == simulationStartTime ? _self.simulationStartTime : simulationStartTime // ignore: cast_nullable_to_non_nullable
as DateTime?,requestedDuration: freezed == requestedDuration ? _self.requestedDuration : requestedDuration // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

/// Create a copy of PipelineState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeployReadinessResultCopyWith<$Res>? get deployReadinessResult {
    if (_self.deployReadinessResult == null) {
    return null;
  }

  return $DeployReadinessResultCopyWith<$Res>(_self.deployReadinessResult!, (value) {
    return _then(_self.copyWith(deployReadinessResult: value));
  });
}
}

// dart format on
