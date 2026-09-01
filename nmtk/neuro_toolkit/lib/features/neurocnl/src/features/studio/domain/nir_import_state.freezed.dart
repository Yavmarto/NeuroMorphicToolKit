// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'nir_import_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
NirImportState _$NirImportStateFromJson(
  Map<String, dynamic> json
) {
        switch (json['status']) {
                  case 'loading':
          return NirImportLoading.fromJson(
            json
          );
                case 'loaded':
          return NirImportLoaded.fromJson(
            json
          );
                case 'error':
          return NirImportError.fromJson(
            json
          );

          default:
            return NirImportIdle.fromJson(
  json
);
        }

}

/// @nodoc
mixin _$NirImportState {



  /// Serializes this NirImportState to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NirImportState);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'NirImportState()';
}


}

/// @nodoc
class $NirImportStateCopyWith<$Res>  {
$NirImportStateCopyWith(NirImportState _, $Res Function(NirImportState) __);
}


/// Adds pattern-matching-related methods to [NirImportState].
extension NirImportStatePatterns on NirImportState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( NirImportIdle value)?  idle,TResult Function( NirImportLoading value)?  loading,TResult Function( NirImportLoaded value)?  loaded,TResult Function( NirImportError value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case NirImportIdle() when idle != null:
return idle(_that);case NirImportLoading() when loading != null:
return loading(_that);case NirImportLoaded() when loaded != null:
return loaded(_that);case NirImportError() when error != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( NirImportIdle value)  idle,required TResult Function( NirImportLoading value)  loading,required TResult Function( NirImportLoaded value)  loaded,required TResult Function( NirImportError value)  error,}){
final _that = this;
switch (_that) {
case NirImportIdle():
return idle(_that);case NirImportLoading():
return loading(_that);case NirImportLoaded():
return loaded(_that);case NirImportError():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( NirImportIdle value)?  idle,TResult? Function( NirImportLoading value)?  loading,TResult? Function( NirImportLoaded value)?  loaded,TResult? Function( NirImportError value)?  error,}){
final _that = this;
switch (_that) {
case NirImportIdle() when idle != null:
return idle(_that);case NirImportLoading() when loading != null:
return loading(_that);case NirImportLoaded() when loaded != null:
return loaded(_that);case NirImportError() when error != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function( NirSource source)?  loading,TResult Function(@JsonKey(fromJson: _nirInspectResultFromJson, toJson: _nirInspectResultToJson)  NirInspectResult result,  NirSource source,  bool writeBackConsumed, @Uint8ListConverter()  Uint8List? rawBytes,  String importId)?  loaded,TResult Function( String error,  NirSource source)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case NirImportIdle() when idle != null:
return idle();case NirImportLoading() when loading != null:
return loading(_that.source);case NirImportLoaded() when loaded != null:
return loaded(_that.result,_that.source,_that.writeBackConsumed,_that.rawBytes,_that.importId);case NirImportError() when error != null:
return error(_that.error,_that.source);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function( NirSource source)  loading,required TResult Function(@JsonKey(fromJson: _nirInspectResultFromJson, toJson: _nirInspectResultToJson)  NirInspectResult result,  NirSource source,  bool writeBackConsumed, @Uint8ListConverter()  Uint8List? rawBytes,  String importId)  loaded,required TResult Function( String error,  NirSource source)  error,}) {final _that = this;
switch (_that) {
case NirImportIdle():
return idle();case NirImportLoading():
return loading(_that.source);case NirImportLoaded():
return loaded(_that.result,_that.source,_that.writeBackConsumed,_that.rawBytes,_that.importId);case NirImportError():
return error(_that.error,_that.source);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function( NirSource source)?  loading,TResult? Function(@JsonKey(fromJson: _nirInspectResultFromJson, toJson: _nirInspectResultToJson)  NirInspectResult result,  NirSource source,  bool writeBackConsumed, @Uint8ListConverter()  Uint8List? rawBytes,  String importId)?  loaded,TResult? Function( String error,  NirSource source)?  error,}) {final _that = this;
switch (_that) {
case NirImportIdle() when idle != null:
return idle();case NirImportLoading() when loading != null:
return loading(_that.source);case NirImportLoaded() when loaded != null:
return loaded(_that.result,_that.source,_that.writeBackConsumed,_that.rawBytes,_that.importId);case NirImportError() when error != null:
return error(_that.error,_that.source);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class NirImportIdle extends NirImportState {
  const NirImportIdle({final  String? $type}): $type = $type ?? 'idle',super._();
  factory NirImportIdle.fromJson(Map<String, dynamic> json) => _$NirImportIdleFromJson(json);



@JsonKey(name: 'status')
final String $type;



@override
Map<String, dynamic> toJson() {
  return _$NirImportIdleToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NirImportIdle);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'NirImportState.idle()';
}


}




/// @nodoc
@JsonSerializable()

class NirImportLoading extends NirImportState {
  const NirImportLoading({this.source = NirSource.none, final  String? $type}): $type = $type ?? 'loading',super._();
  factory NirImportLoading.fromJson(Map<String, dynamic> json) => _$NirImportLoadingFromJson(json);

@JsonKey() final  NirSource source;

@JsonKey(name: 'status')
final String $type;


/// Create a copy of NirImportState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NirImportLoadingCopyWith<NirImportLoading> get copyWith => _$NirImportLoadingCopyWithImpl<NirImportLoading>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$NirImportLoadingToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NirImportLoading&&(identical(other.source, source) || other.source == source));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,source);

@override
String toString() {
  return 'NirImportState.loading(source: $source)';
}


}

/// @nodoc
abstract mixin class $NirImportLoadingCopyWith<$Res> implements $NirImportStateCopyWith<$Res> {
  factory $NirImportLoadingCopyWith(NirImportLoading value, $Res Function(NirImportLoading) _then) = _$NirImportLoadingCopyWithImpl;
@useResult
$Res call({
 NirSource source
});




}
/// @nodoc
class _$NirImportLoadingCopyWithImpl<$Res>
    implements $NirImportLoadingCopyWith<$Res> {
  _$NirImportLoadingCopyWithImpl(this._self, this._then);

  final NirImportLoading _self;
  final $Res Function(NirImportLoading) _then;

/// Create a copy of NirImportState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? source = null,}) {
  return _then(NirImportLoading(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as NirSource,
  ));
}


}

/// @nodoc
@JsonSerializable()

class NirImportLoaded extends NirImportState {
  const NirImportLoaded({@JsonKey(fromJson: _nirInspectResultFromJson, toJson: _nirInspectResultToJson) required this.result, this.source = NirSource.none, this.writeBackConsumed = false, @Uint8ListConverter() this.rawBytes, this.importId = '', final  String? $type}): $type = $type ?? 'loaded',super._();
  factory NirImportLoaded.fromJson(Map<String, dynamic> json) => _$NirImportLoadedFromJson(json);

@JsonKey(fromJson: _nirInspectResultFromJson, toJson: _nirInspectResultToJson) final  NirInspectResult result;
@JsonKey() final  NirSource source;
@JsonKey() final  bool writeBackConsumed;
@Uint8ListConverter() final  Uint8List? rawBytes;
@JsonKey() final  String importId;

@JsonKey(name: 'status')
final String $type;


/// Create a copy of NirImportState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NirImportLoadedCopyWith<NirImportLoaded> get copyWith => _$NirImportLoadedCopyWithImpl<NirImportLoaded>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$NirImportLoadedToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NirImportLoaded&&(identical(other.result, result) || other.result == result)&&(identical(other.source, source) || other.source == source)&&(identical(other.writeBackConsumed, writeBackConsumed) || other.writeBackConsumed == writeBackConsumed)&&const DeepCollectionEquality().equals(other.rawBytes, rawBytes)&&(identical(other.importId, importId) || other.importId == importId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,result,source,writeBackConsumed,const DeepCollectionEquality().hash(rawBytes),importId);

@override
String toString() {
  return 'NirImportState.loaded(result: $result, source: $source, writeBackConsumed: $writeBackConsumed, rawBytes: $rawBytes, importId: $importId)';
}


}

/// @nodoc
abstract mixin class $NirImportLoadedCopyWith<$Res> implements $NirImportStateCopyWith<$Res> {
  factory $NirImportLoadedCopyWith(NirImportLoaded value, $Res Function(NirImportLoaded) _then) = _$NirImportLoadedCopyWithImpl;
@useResult
$Res call({
@JsonKey(fromJson: _nirInspectResultFromJson, toJson: _nirInspectResultToJson) NirInspectResult result, NirSource source, bool writeBackConsumed,@Uint8ListConverter() Uint8List? rawBytes, String importId
});




}
/// @nodoc
class _$NirImportLoadedCopyWithImpl<$Res>
    implements $NirImportLoadedCopyWith<$Res> {
  _$NirImportLoadedCopyWithImpl(this._self, this._then);

  final NirImportLoaded _self;
  final $Res Function(NirImportLoaded) _then;

/// Create a copy of NirImportState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? result = null,Object? source = null,Object? writeBackConsumed = null,Object? rawBytes = freezed,Object? importId = null,}) {
  return _then(NirImportLoaded(
result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as NirInspectResult,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as NirSource,writeBackConsumed: null == writeBackConsumed ? _self.writeBackConsumed : writeBackConsumed // ignore: cast_nullable_to_non_nullable
as bool,rawBytes: freezed == rawBytes ? _self.rawBytes : rawBytes // ignore: cast_nullable_to_non_nullable
as Uint8List?,importId: null == importId ? _self.importId : importId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
@JsonSerializable()

class NirImportError extends NirImportState {
  const NirImportError({required this.error, this.source = NirSource.none, final  String? $type}): $type = $type ?? 'error',super._();
  factory NirImportError.fromJson(Map<String, dynamic> json) => _$NirImportErrorFromJson(json);

 final  String error;
@JsonKey() final  NirSource source;

@JsonKey(name: 'status')
final String $type;


/// Create a copy of NirImportState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NirImportErrorCopyWith<NirImportError> get copyWith => _$NirImportErrorCopyWithImpl<NirImportError>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$NirImportErrorToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NirImportError&&(identical(other.error, error) || other.error == error)&&(identical(other.source, source) || other.source == source));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,error,source);

@override
String toString() {
  return 'NirImportState.error(error: $error, source: $source)';
}


}

/// @nodoc
abstract mixin class $NirImportErrorCopyWith<$Res> implements $NirImportStateCopyWith<$Res> {
  factory $NirImportErrorCopyWith(NirImportError value, $Res Function(NirImportError) _then) = _$NirImportErrorCopyWithImpl;
@useResult
$Res call({
 String error, NirSource source
});




}
/// @nodoc
class _$NirImportErrorCopyWithImpl<$Res>
    implements $NirImportErrorCopyWith<$Res> {
  _$NirImportErrorCopyWithImpl(this._self, this._then);

  final NirImportError _self;
  final $Res Function(NirImportError) _then;

/// Create a copy of NirImportState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,Object? source = null,}) {
  return _then(NirImportError(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as NirSource,
  ));
}


}

// dart format on
