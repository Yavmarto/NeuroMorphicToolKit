// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'workspace_file.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$WorkspacePipelineCache {

 String get sourceHash; String get generatedAt;@JsonKey(fromJson: _generateResultFromJson, toJson: _generateResultToJson) GenerateResult get generateResult; String? get simulatedAt;@JsonKey(fromJson: _simulationResultFromJson, toJson: _simulationResultToJson) SimulationResult? get simulationResult;
/// Create a copy of WorkspacePipelineCache
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspacePipelineCacheCopyWith<WorkspacePipelineCache> get copyWith => _$WorkspacePipelineCacheCopyWithImpl<WorkspacePipelineCache>(this as WorkspacePipelineCache, _$identity);

  /// Serializes this WorkspacePipelineCache to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspacePipelineCache&&(identical(other.sourceHash, sourceHash) || other.sourceHash == sourceHash)&&(identical(other.generatedAt, generatedAt) || other.generatedAt == generatedAt)&&(identical(other.generateResult, generateResult) || other.generateResult == generateResult)&&(identical(other.simulatedAt, simulatedAt) || other.simulatedAt == simulatedAt)&&(identical(other.simulationResult, simulationResult) || other.simulationResult == simulationResult));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,sourceHash,generatedAt,generateResult,simulatedAt,simulationResult);

@override
String toString() {
  return 'WorkspacePipelineCache(sourceHash: $sourceHash, generatedAt: $generatedAt, generateResult: $generateResult, simulatedAt: $simulatedAt, simulationResult: $simulationResult)';
}


}

/// @nodoc
abstract mixin class $WorkspacePipelineCacheCopyWith<$Res>  {
  factory $WorkspacePipelineCacheCopyWith(WorkspacePipelineCache value, $Res Function(WorkspacePipelineCache) _then) = _$WorkspacePipelineCacheCopyWithImpl;
@useResult
$Res call({
 String sourceHash, String generatedAt,@JsonKey(fromJson: _generateResultFromJson, toJson: _generateResultToJson) GenerateResult generateResult, String? simulatedAt,@JsonKey(fromJson: _simulationResultFromJson, toJson: _simulationResultToJson) SimulationResult? simulationResult
});




}
/// @nodoc
class _$WorkspacePipelineCacheCopyWithImpl<$Res>
    implements $WorkspacePipelineCacheCopyWith<$Res> {
  _$WorkspacePipelineCacheCopyWithImpl(this._self, this._then);

  final WorkspacePipelineCache _self;
  final $Res Function(WorkspacePipelineCache) _then;

/// Create a copy of WorkspacePipelineCache
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sourceHash = null,Object? generatedAt = null,Object? generateResult = null,Object? simulatedAt = freezed,Object? simulationResult = freezed,}) {
  return _then(_self.copyWith(
sourceHash: null == sourceHash ? _self.sourceHash : sourceHash // ignore: cast_nullable_to_non_nullable
as String,generatedAt: null == generatedAt ? _self.generatedAt : generatedAt // ignore: cast_nullable_to_non_nullable
as String,generateResult: null == generateResult ? _self.generateResult : generateResult // ignore: cast_nullable_to_non_nullable
as GenerateResult,simulatedAt: freezed == simulatedAt ? _self.simulatedAt : simulatedAt // ignore: cast_nullable_to_non_nullable
as String?,simulationResult: freezed == simulationResult ? _self.simulationResult : simulationResult // ignore: cast_nullable_to_non_nullable
as SimulationResult?,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkspacePipelineCache].
extension WorkspacePipelineCachePatterns on WorkspacePipelineCache {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkspacePipelineCache value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkspacePipelineCache() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkspacePipelineCache value)  $default,){
final _that = this;
switch (_that) {
case _WorkspacePipelineCache():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkspacePipelineCache value)?  $default,){
final _that = this;
switch (_that) {
case _WorkspacePipelineCache() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sourceHash,  String generatedAt, @JsonKey(fromJson: _generateResultFromJson, toJson: _generateResultToJson)  GenerateResult generateResult,  String? simulatedAt, @JsonKey(fromJson: _simulationResultFromJson, toJson: _simulationResultToJson)  SimulationResult? simulationResult)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkspacePipelineCache() when $default != null:
return $default(_that.sourceHash,_that.generatedAt,_that.generateResult,_that.simulatedAt,_that.simulationResult);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sourceHash,  String generatedAt, @JsonKey(fromJson: _generateResultFromJson, toJson: _generateResultToJson)  GenerateResult generateResult,  String? simulatedAt, @JsonKey(fromJson: _simulationResultFromJson, toJson: _simulationResultToJson)  SimulationResult? simulationResult)  $default,) {final _that = this;
switch (_that) {
case _WorkspacePipelineCache():
return $default(_that.sourceHash,_that.generatedAt,_that.generateResult,_that.simulatedAt,_that.simulationResult);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sourceHash,  String generatedAt, @JsonKey(fromJson: _generateResultFromJson, toJson: _generateResultToJson)  GenerateResult generateResult,  String? simulatedAt, @JsonKey(fromJson: _simulationResultFromJson, toJson: _simulationResultToJson)  SimulationResult? simulationResult)?  $default,) {final _that = this;
switch (_that) {
case _WorkspacePipelineCache() when $default != null:
return $default(_that.sourceHash,_that.generatedAt,_that.generateResult,_that.simulatedAt,_that.simulationResult);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WorkspacePipelineCache extends WorkspacePipelineCache {
  const _WorkspacePipelineCache({required this.sourceHash, required this.generatedAt, @JsonKey(fromJson: _generateResultFromJson, toJson: _generateResultToJson) required this.generateResult, this.simulatedAt, @JsonKey(fromJson: _simulationResultFromJson, toJson: _simulationResultToJson) this.simulationResult}): super._();
  factory _WorkspacePipelineCache.fromJson(Map<String, dynamic> json) => _$WorkspacePipelineCacheFromJson(json);

@override final  String sourceHash;
@override final  String generatedAt;
@override@JsonKey(fromJson: _generateResultFromJson, toJson: _generateResultToJson) final  GenerateResult generateResult;
@override final  String? simulatedAt;
@override@JsonKey(fromJson: _simulationResultFromJson, toJson: _simulationResultToJson) final  SimulationResult? simulationResult;

/// Create a copy of WorkspacePipelineCache
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkspacePipelineCacheCopyWith<_WorkspacePipelineCache> get copyWith => __$WorkspacePipelineCacheCopyWithImpl<_WorkspacePipelineCache>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WorkspacePipelineCacheToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkspacePipelineCache&&(identical(other.sourceHash, sourceHash) || other.sourceHash == sourceHash)&&(identical(other.generatedAt, generatedAt) || other.generatedAt == generatedAt)&&(identical(other.generateResult, generateResult) || other.generateResult == generateResult)&&(identical(other.simulatedAt, simulatedAt) || other.simulatedAt == simulatedAt)&&(identical(other.simulationResult, simulationResult) || other.simulationResult == simulationResult));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,sourceHash,generatedAt,generateResult,simulatedAt,simulationResult);

@override
String toString() {
  return 'WorkspacePipelineCache(sourceHash: $sourceHash, generatedAt: $generatedAt, generateResult: $generateResult, simulatedAt: $simulatedAt, simulationResult: $simulationResult)';
}


}

/// @nodoc
abstract mixin class _$WorkspacePipelineCacheCopyWith<$Res> implements $WorkspacePipelineCacheCopyWith<$Res> {
  factory _$WorkspacePipelineCacheCopyWith(_WorkspacePipelineCache value, $Res Function(_WorkspacePipelineCache) _then) = __$WorkspacePipelineCacheCopyWithImpl;
@override @useResult
$Res call({
 String sourceHash, String generatedAt,@JsonKey(fromJson: _generateResultFromJson, toJson: _generateResultToJson) GenerateResult generateResult, String? simulatedAt,@JsonKey(fromJson: _simulationResultFromJson, toJson: _simulationResultToJson) SimulationResult? simulationResult
});




}
/// @nodoc
class __$WorkspacePipelineCacheCopyWithImpl<$Res>
    implements _$WorkspacePipelineCacheCopyWith<$Res> {
  __$WorkspacePipelineCacheCopyWithImpl(this._self, this._then);

  final _WorkspacePipelineCache _self;
  final $Res Function(_WorkspacePipelineCache) _then;

/// Create a copy of WorkspacePipelineCache
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sourceHash = null,Object? generatedAt = null,Object? generateResult = null,Object? simulatedAt = freezed,Object? simulationResult = freezed,}) {
  return _then(_WorkspacePipelineCache(
sourceHash: null == sourceHash ? _self.sourceHash : sourceHash // ignore: cast_nullable_to_non_nullable
as String,generatedAt: null == generatedAt ? _self.generatedAt : generatedAt // ignore: cast_nullable_to_non_nullable
as String,generateResult: null == generateResult ? _self.generateResult : generateResult // ignore: cast_nullable_to_non_nullable
as GenerateResult,simulatedAt: freezed == simulatedAt ? _self.simulatedAt : simulatedAt // ignore: cast_nullable_to_non_nullable
as String?,simulationResult: freezed == simulationResult ? _self.simulationResult : simulationResult // ignore: cast_nullable_to_non_nullable
as SimulationResult?,
  ));
}


}


/// @nodoc
mixin _$WorkspaceNirArtifactCache {

 String get sourceHash; String get savedAt; String get filename; String get mimeType; String get payloadBase64;
/// Create a copy of WorkspaceNirArtifactCache
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceNirArtifactCacheCopyWith<WorkspaceNirArtifactCache> get copyWith => _$WorkspaceNirArtifactCacheCopyWithImpl<WorkspaceNirArtifactCache>(this as WorkspaceNirArtifactCache, _$identity);

  /// Serializes this WorkspaceNirArtifactCache to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceNirArtifactCache&&(identical(other.sourceHash, sourceHash) || other.sourceHash == sourceHash)&&(identical(other.savedAt, savedAt) || other.savedAt == savedAt)&&(identical(other.filename, filename) || other.filename == filename)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.payloadBase64, payloadBase64) || other.payloadBase64 == payloadBase64));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,sourceHash,savedAt,filename,mimeType,payloadBase64);

@override
String toString() {
  return 'WorkspaceNirArtifactCache(sourceHash: $sourceHash, savedAt: $savedAt, filename: $filename, mimeType: $mimeType, payloadBase64: $payloadBase64)';
}


}

/// @nodoc
abstract mixin class $WorkspaceNirArtifactCacheCopyWith<$Res>  {
  factory $WorkspaceNirArtifactCacheCopyWith(WorkspaceNirArtifactCache value, $Res Function(WorkspaceNirArtifactCache) _then) = _$WorkspaceNirArtifactCacheCopyWithImpl;
@useResult
$Res call({
 String sourceHash, String savedAt, String filename, String mimeType, String payloadBase64
});




}
/// @nodoc
class _$WorkspaceNirArtifactCacheCopyWithImpl<$Res>
    implements $WorkspaceNirArtifactCacheCopyWith<$Res> {
  _$WorkspaceNirArtifactCacheCopyWithImpl(this._self, this._then);

  final WorkspaceNirArtifactCache _self;
  final $Res Function(WorkspaceNirArtifactCache) _then;

/// Create a copy of WorkspaceNirArtifactCache
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sourceHash = null,Object? savedAt = null,Object? filename = null,Object? mimeType = null,Object? payloadBase64 = null,}) {
  return _then(_self.copyWith(
sourceHash: null == sourceHash ? _self.sourceHash : sourceHash // ignore: cast_nullable_to_non_nullable
as String,savedAt: null == savedAt ? _self.savedAt : savedAt // ignore: cast_nullable_to_non_nullable
as String,filename: null == filename ? _self.filename : filename // ignore: cast_nullable_to_non_nullable
as String,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,payloadBase64: null == payloadBase64 ? _self.payloadBase64 : payloadBase64 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkspaceNirArtifactCache].
extension WorkspaceNirArtifactCachePatterns on WorkspaceNirArtifactCache {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkspaceNirArtifactCache value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkspaceNirArtifactCache() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkspaceNirArtifactCache value)  $default,){
final _that = this;
switch (_that) {
case _WorkspaceNirArtifactCache():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkspaceNirArtifactCache value)?  $default,){
final _that = this;
switch (_that) {
case _WorkspaceNirArtifactCache() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sourceHash,  String savedAt,  String filename,  String mimeType,  String payloadBase64)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkspaceNirArtifactCache() when $default != null:
return $default(_that.sourceHash,_that.savedAt,_that.filename,_that.mimeType,_that.payloadBase64);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sourceHash,  String savedAt,  String filename,  String mimeType,  String payloadBase64)  $default,) {final _that = this;
switch (_that) {
case _WorkspaceNirArtifactCache():
return $default(_that.sourceHash,_that.savedAt,_that.filename,_that.mimeType,_that.payloadBase64);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sourceHash,  String savedAt,  String filename,  String mimeType,  String payloadBase64)?  $default,) {final _that = this;
switch (_that) {
case _WorkspaceNirArtifactCache() when $default != null:
return $default(_that.sourceHash,_that.savedAt,_that.filename,_that.mimeType,_that.payloadBase64);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WorkspaceNirArtifactCache extends WorkspaceNirArtifactCache {
  const _WorkspaceNirArtifactCache({required this.sourceHash, required this.savedAt, this.filename = 'network.nir', this.mimeType = 'application/octet-stream', required this.payloadBase64}): super._();
  factory _WorkspaceNirArtifactCache.fromJson(Map<String, dynamic> json) => _$WorkspaceNirArtifactCacheFromJson(json);

@override final  String sourceHash;
@override final  String savedAt;
@override@JsonKey() final  String filename;
@override@JsonKey() final  String mimeType;
@override final  String payloadBase64;

/// Create a copy of WorkspaceNirArtifactCache
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkspaceNirArtifactCacheCopyWith<_WorkspaceNirArtifactCache> get copyWith => __$WorkspaceNirArtifactCacheCopyWithImpl<_WorkspaceNirArtifactCache>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WorkspaceNirArtifactCacheToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkspaceNirArtifactCache&&(identical(other.sourceHash, sourceHash) || other.sourceHash == sourceHash)&&(identical(other.savedAt, savedAt) || other.savedAt == savedAt)&&(identical(other.filename, filename) || other.filename == filename)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.payloadBase64, payloadBase64) || other.payloadBase64 == payloadBase64));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,sourceHash,savedAt,filename,mimeType,payloadBase64);

@override
String toString() {
  return 'WorkspaceNirArtifactCache(sourceHash: $sourceHash, savedAt: $savedAt, filename: $filename, mimeType: $mimeType, payloadBase64: $payloadBase64)';
}


}

/// @nodoc
abstract mixin class _$WorkspaceNirArtifactCacheCopyWith<$Res> implements $WorkspaceNirArtifactCacheCopyWith<$Res> {
  factory _$WorkspaceNirArtifactCacheCopyWith(_WorkspaceNirArtifactCache value, $Res Function(_WorkspaceNirArtifactCache) _then) = __$WorkspaceNirArtifactCacheCopyWithImpl;
@override @useResult
$Res call({
 String sourceHash, String savedAt, String filename, String mimeType, String payloadBase64
});




}
/// @nodoc
class __$WorkspaceNirArtifactCacheCopyWithImpl<$Res>
    implements _$WorkspaceNirArtifactCacheCopyWith<$Res> {
  __$WorkspaceNirArtifactCacheCopyWithImpl(this._self, this._then);

  final _WorkspaceNirArtifactCache _self;
  final $Res Function(_WorkspaceNirArtifactCache) _then;

/// Create a copy of WorkspaceNirArtifactCache
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sourceHash = null,Object? savedAt = null,Object? filename = null,Object? mimeType = null,Object? payloadBase64 = null,}) {
  return _then(_WorkspaceNirArtifactCache(
sourceHash: null == sourceHash ? _self.sourceHash : sourceHash // ignore: cast_nullable_to_non_nullable
as String,savedAt: null == savedAt ? _self.savedAt : savedAt // ignore: cast_nullable_to_non_nullable
as String,filename: null == filename ? _self.filename : filename // ignore: cast_nullable_to_non_nullable
as String,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,payloadBase64: null == payloadBase64 ? _self.payloadBase64 : payloadBase64 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$WorkspaceFile {

 String get id; String get name; String? get path; bool get dirty; bool get isUntitled; int get cursorOffset; int get selectionBase; int get selectionExtent; double get scrollOffset;@JsonKey(fromJson: _pipelineCacheFromJson, toJson: _pipelineCacheToJson) WorkspacePipelineCache? get pipelineCache;@JsonKey(fromJson: _nirArtifactCacheFromJson, toJson: _nirArtifactCacheToJson) WorkspaceNirArtifactCache? get nirArtifactCache;// Complex types with manual serializers — use @JsonKey to wire up helpers.
@JsonKey(fromJson: _pipelineStateFromJson, toJson: _pipelineStateToJson) PipelineState? get pipelineState;@JsonKey(fromJson: _canonicalDocFromJson, toJson: _canonicalDocToJson) CanonicalEditorDocument? get canonicalDocument; int get revision;
/// Create a copy of WorkspaceFile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceFileCopyWith<WorkspaceFile> get copyWith => _$WorkspaceFileCopyWithImpl<WorkspaceFile>(this as WorkspaceFile, _$identity);

  /// Serializes this WorkspaceFile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceFile&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.path, path) || other.path == path)&&(identical(other.dirty, dirty) || other.dirty == dirty)&&(identical(other.isUntitled, isUntitled) || other.isUntitled == isUntitled)&&(identical(other.cursorOffset, cursorOffset) || other.cursorOffset == cursorOffset)&&(identical(other.selectionBase, selectionBase) || other.selectionBase == selectionBase)&&(identical(other.selectionExtent, selectionExtent) || other.selectionExtent == selectionExtent)&&(identical(other.scrollOffset, scrollOffset) || other.scrollOffset == scrollOffset)&&(identical(other.pipelineCache, pipelineCache) || other.pipelineCache == pipelineCache)&&(identical(other.nirArtifactCache, nirArtifactCache) || other.nirArtifactCache == nirArtifactCache)&&(identical(other.pipelineState, pipelineState) || other.pipelineState == pipelineState)&&(identical(other.canonicalDocument, canonicalDocument) || other.canonicalDocument == canonicalDocument)&&(identical(other.revision, revision) || other.revision == revision));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,path,dirty,isUntitled,cursorOffset,selectionBase,selectionExtent,scrollOffset,pipelineCache,nirArtifactCache,pipelineState,canonicalDocument,revision);

@override
String toString() {
  return 'WorkspaceFile(id: $id, name: $name, path: $path, dirty: $dirty, isUntitled: $isUntitled, cursorOffset: $cursorOffset, selectionBase: $selectionBase, selectionExtent: $selectionExtent, scrollOffset: $scrollOffset, pipelineCache: $pipelineCache, nirArtifactCache: $nirArtifactCache, pipelineState: $pipelineState, canonicalDocument: $canonicalDocument, revision: $revision)';
}


}

/// @nodoc
abstract mixin class $WorkspaceFileCopyWith<$Res>  {
  factory $WorkspaceFileCopyWith(WorkspaceFile value, $Res Function(WorkspaceFile) _then) = _$WorkspaceFileCopyWithImpl;
@useResult
$Res call({
 String id, String name, String? path, bool dirty, bool isUntitled, int cursorOffset, int selectionBase, int selectionExtent, double scrollOffset,@JsonKey(fromJson: _pipelineCacheFromJson, toJson: _pipelineCacheToJson) WorkspacePipelineCache? pipelineCache,@JsonKey(fromJson: _nirArtifactCacheFromJson, toJson: _nirArtifactCacheToJson) WorkspaceNirArtifactCache? nirArtifactCache,@JsonKey(fromJson: _pipelineStateFromJson, toJson: _pipelineStateToJson) PipelineState? pipelineState,@JsonKey(fromJson: _canonicalDocFromJson, toJson: _canonicalDocToJson) CanonicalEditorDocument? canonicalDocument, int revision
});


$WorkspacePipelineCacheCopyWith<$Res>? get pipelineCache;$WorkspaceNirArtifactCacheCopyWith<$Res>? get nirArtifactCache;$PipelineStateCopyWith<$Res>? get pipelineState;

}
/// @nodoc
class _$WorkspaceFileCopyWithImpl<$Res>
    implements $WorkspaceFileCopyWith<$Res> {
  _$WorkspaceFileCopyWithImpl(this._self, this._then);

  final WorkspaceFile _self;
  final $Res Function(WorkspaceFile) _then;

/// Create a copy of WorkspaceFile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? path = freezed,Object? dirty = null,Object? isUntitled = null,Object? cursorOffset = null,Object? selectionBase = null,Object? selectionExtent = null,Object? scrollOffset = null,Object? pipelineCache = freezed,Object? nirArtifactCache = freezed,Object? pipelineState = freezed,Object? canonicalDocument = freezed,Object? revision = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,path: freezed == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String?,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,isUntitled: null == isUntitled ? _self.isUntitled : isUntitled // ignore: cast_nullable_to_non_nullable
as bool,cursorOffset: null == cursorOffset ? _self.cursorOffset : cursorOffset // ignore: cast_nullable_to_non_nullable
as int,selectionBase: null == selectionBase ? _self.selectionBase : selectionBase // ignore: cast_nullable_to_non_nullable
as int,selectionExtent: null == selectionExtent ? _self.selectionExtent : selectionExtent // ignore: cast_nullable_to_non_nullable
as int,scrollOffset: null == scrollOffset ? _self.scrollOffset : scrollOffset // ignore: cast_nullable_to_non_nullable
as double,pipelineCache: freezed == pipelineCache ? _self.pipelineCache : pipelineCache // ignore: cast_nullable_to_non_nullable
as WorkspacePipelineCache?,nirArtifactCache: freezed == nirArtifactCache ? _self.nirArtifactCache : nirArtifactCache // ignore: cast_nullable_to_non_nullable
as WorkspaceNirArtifactCache?,pipelineState: freezed == pipelineState ? _self.pipelineState : pipelineState // ignore: cast_nullable_to_non_nullable
as PipelineState?,canonicalDocument: freezed == canonicalDocument ? _self.canonicalDocument : canonicalDocument // ignore: cast_nullable_to_non_nullable
as CanonicalEditorDocument?,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of WorkspaceFile
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspacePipelineCacheCopyWith<$Res>? get pipelineCache {
    if (_self.pipelineCache == null) {
    return null;
  }

  return $WorkspacePipelineCacheCopyWith<$Res>(_self.pipelineCache!, (value) {
    return _then(_self.copyWith(pipelineCache: value));
  });
}/// Create a copy of WorkspaceFile
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceNirArtifactCacheCopyWith<$Res>? get nirArtifactCache {
    if (_self.nirArtifactCache == null) {
    return null;
  }

  return $WorkspaceNirArtifactCacheCopyWith<$Res>(_self.nirArtifactCache!, (value) {
    return _then(_self.copyWith(nirArtifactCache: value));
  });
}/// Create a copy of WorkspaceFile
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PipelineStateCopyWith<$Res>? get pipelineState {
    if (_self.pipelineState == null) {
    return null;
  }

  return $PipelineStateCopyWith<$Res>(_self.pipelineState!, (value) {
    return _then(_self.copyWith(pipelineState: value));
  });
}
}


/// Adds pattern-matching-related methods to [WorkspaceFile].
extension WorkspaceFilePatterns on WorkspaceFile {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkspaceFile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkspaceFile() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkspaceFile value)  $default,){
final _that = this;
switch (_that) {
case _WorkspaceFile():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkspaceFile value)?  $default,){
final _that = this;
switch (_that) {
case _WorkspaceFile() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String? path,  bool dirty,  bool isUntitled,  int cursorOffset,  int selectionBase,  int selectionExtent,  double scrollOffset, @JsonKey(fromJson: _pipelineCacheFromJson, toJson: _pipelineCacheToJson)  WorkspacePipelineCache? pipelineCache, @JsonKey(fromJson: _nirArtifactCacheFromJson, toJson: _nirArtifactCacheToJson)  WorkspaceNirArtifactCache? nirArtifactCache, @JsonKey(fromJson: _pipelineStateFromJson, toJson: _pipelineStateToJson)  PipelineState? pipelineState, @JsonKey(fromJson: _canonicalDocFromJson, toJson: _canonicalDocToJson)  CanonicalEditorDocument? canonicalDocument,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkspaceFile() when $default != null:
return $default(_that.id,_that.name,_that.path,_that.dirty,_that.isUntitled,_that.cursorOffset,_that.selectionBase,_that.selectionExtent,_that.scrollOffset,_that.pipelineCache,_that.nirArtifactCache,_that.pipelineState,_that.canonicalDocument,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String? path,  bool dirty,  bool isUntitled,  int cursorOffset,  int selectionBase,  int selectionExtent,  double scrollOffset, @JsonKey(fromJson: _pipelineCacheFromJson, toJson: _pipelineCacheToJson)  WorkspacePipelineCache? pipelineCache, @JsonKey(fromJson: _nirArtifactCacheFromJson, toJson: _nirArtifactCacheToJson)  WorkspaceNirArtifactCache? nirArtifactCache, @JsonKey(fromJson: _pipelineStateFromJson, toJson: _pipelineStateToJson)  PipelineState? pipelineState, @JsonKey(fromJson: _canonicalDocFromJson, toJson: _canonicalDocToJson)  CanonicalEditorDocument? canonicalDocument,  int revision)  $default,) {final _that = this;
switch (_that) {
case _WorkspaceFile():
return $default(_that.id,_that.name,_that.path,_that.dirty,_that.isUntitled,_that.cursorOffset,_that.selectionBase,_that.selectionExtent,_that.scrollOffset,_that.pipelineCache,_that.nirArtifactCache,_that.pipelineState,_that.canonicalDocument,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String? path,  bool dirty,  bool isUntitled,  int cursorOffset,  int selectionBase,  int selectionExtent,  double scrollOffset, @JsonKey(fromJson: _pipelineCacheFromJson, toJson: _pipelineCacheToJson)  WorkspacePipelineCache? pipelineCache, @JsonKey(fromJson: _nirArtifactCacheFromJson, toJson: _nirArtifactCacheToJson)  WorkspaceNirArtifactCache? nirArtifactCache, @JsonKey(fromJson: _pipelineStateFromJson, toJson: _pipelineStateToJson)  PipelineState? pipelineState, @JsonKey(fromJson: _canonicalDocFromJson, toJson: _canonicalDocToJson)  CanonicalEditorDocument? canonicalDocument,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _WorkspaceFile() when $default != null:
return $default(_that.id,_that.name,_that.path,_that.dirty,_that.isUntitled,_that.cursorOffset,_that.selectionBase,_that.selectionExtent,_that.scrollOffset,_that.pipelineCache,_that.nirArtifactCache,_that.pipelineState,_that.canonicalDocument,_that.revision);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WorkspaceFile extends WorkspaceFile {
  const _WorkspaceFile({this.id = '', this.name = 'Untitled', this.path, this.dirty = false, this.isUntitled = true, this.cursorOffset = 0, this.selectionBase = 0, this.selectionExtent = 0, this.scrollOffset = 0.0, @JsonKey(fromJson: _pipelineCacheFromJson, toJson: _pipelineCacheToJson) this.pipelineCache, @JsonKey(fromJson: _nirArtifactCacheFromJson, toJson: _nirArtifactCacheToJson) this.nirArtifactCache, @JsonKey(fromJson: _pipelineStateFromJson, toJson: _pipelineStateToJson) this.pipelineState, @JsonKey(fromJson: _canonicalDocFromJson, toJson: _canonicalDocToJson) this.canonicalDocument, this.revision = 0}): super._();
  factory _WorkspaceFile.fromJson(Map<String, dynamic> json) => _$WorkspaceFileFromJson(json);

@override@JsonKey() final  String id;
@override@JsonKey() final  String name;
@override final  String? path;
@override@JsonKey() final  bool dirty;
@override@JsonKey() final  bool isUntitled;
@override@JsonKey() final  int cursorOffset;
@override@JsonKey() final  int selectionBase;
@override@JsonKey() final  int selectionExtent;
@override@JsonKey() final  double scrollOffset;
@override@JsonKey(fromJson: _pipelineCacheFromJson, toJson: _pipelineCacheToJson) final  WorkspacePipelineCache? pipelineCache;
@override@JsonKey(fromJson: _nirArtifactCacheFromJson, toJson: _nirArtifactCacheToJson) final  WorkspaceNirArtifactCache? nirArtifactCache;
// Complex types with manual serializers — use @JsonKey to wire up helpers.
@override@JsonKey(fromJson: _pipelineStateFromJson, toJson: _pipelineStateToJson) final  PipelineState? pipelineState;
@override@JsonKey(fromJson: _canonicalDocFromJson, toJson: _canonicalDocToJson) final  CanonicalEditorDocument? canonicalDocument;
@override@JsonKey() final  int revision;

/// Create a copy of WorkspaceFile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkspaceFileCopyWith<_WorkspaceFile> get copyWith => __$WorkspaceFileCopyWithImpl<_WorkspaceFile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WorkspaceFileToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkspaceFile&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.path, path) || other.path == path)&&(identical(other.dirty, dirty) || other.dirty == dirty)&&(identical(other.isUntitled, isUntitled) || other.isUntitled == isUntitled)&&(identical(other.cursorOffset, cursorOffset) || other.cursorOffset == cursorOffset)&&(identical(other.selectionBase, selectionBase) || other.selectionBase == selectionBase)&&(identical(other.selectionExtent, selectionExtent) || other.selectionExtent == selectionExtent)&&(identical(other.scrollOffset, scrollOffset) || other.scrollOffset == scrollOffset)&&(identical(other.pipelineCache, pipelineCache) || other.pipelineCache == pipelineCache)&&(identical(other.nirArtifactCache, nirArtifactCache) || other.nirArtifactCache == nirArtifactCache)&&(identical(other.pipelineState, pipelineState) || other.pipelineState == pipelineState)&&(identical(other.canonicalDocument, canonicalDocument) || other.canonicalDocument == canonicalDocument)&&(identical(other.revision, revision) || other.revision == revision));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,path,dirty,isUntitled,cursorOffset,selectionBase,selectionExtent,scrollOffset,pipelineCache,nirArtifactCache,pipelineState,canonicalDocument,revision);

@override
String toString() {
  return 'WorkspaceFile(id: $id, name: $name, path: $path, dirty: $dirty, isUntitled: $isUntitled, cursorOffset: $cursorOffset, selectionBase: $selectionBase, selectionExtent: $selectionExtent, scrollOffset: $scrollOffset, pipelineCache: $pipelineCache, nirArtifactCache: $nirArtifactCache, pipelineState: $pipelineState, canonicalDocument: $canonicalDocument, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$WorkspaceFileCopyWith<$Res> implements $WorkspaceFileCopyWith<$Res> {
  factory _$WorkspaceFileCopyWith(_WorkspaceFile value, $Res Function(_WorkspaceFile) _then) = __$WorkspaceFileCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? path, bool dirty, bool isUntitled, int cursorOffset, int selectionBase, int selectionExtent, double scrollOffset,@JsonKey(fromJson: _pipelineCacheFromJson, toJson: _pipelineCacheToJson) WorkspacePipelineCache? pipelineCache,@JsonKey(fromJson: _nirArtifactCacheFromJson, toJson: _nirArtifactCacheToJson) WorkspaceNirArtifactCache? nirArtifactCache,@JsonKey(fromJson: _pipelineStateFromJson, toJson: _pipelineStateToJson) PipelineState? pipelineState,@JsonKey(fromJson: _canonicalDocFromJson, toJson: _canonicalDocToJson) CanonicalEditorDocument? canonicalDocument, int revision
});


@override $WorkspacePipelineCacheCopyWith<$Res>? get pipelineCache;@override $WorkspaceNirArtifactCacheCopyWith<$Res>? get nirArtifactCache;@override $PipelineStateCopyWith<$Res>? get pipelineState;

}
/// @nodoc
class __$WorkspaceFileCopyWithImpl<$Res>
    implements _$WorkspaceFileCopyWith<$Res> {
  __$WorkspaceFileCopyWithImpl(this._self, this._then);

  final _WorkspaceFile _self;
  final $Res Function(_WorkspaceFile) _then;

/// Create a copy of WorkspaceFile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? path = freezed,Object? dirty = null,Object? isUntitled = null,Object? cursorOffset = null,Object? selectionBase = null,Object? selectionExtent = null,Object? scrollOffset = null,Object? pipelineCache = freezed,Object? nirArtifactCache = freezed,Object? pipelineState = freezed,Object? canonicalDocument = freezed,Object? revision = null,}) {
  return _then(_WorkspaceFile(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,path: freezed == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String?,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,isUntitled: null == isUntitled ? _self.isUntitled : isUntitled // ignore: cast_nullable_to_non_nullable
as bool,cursorOffset: null == cursorOffset ? _self.cursorOffset : cursorOffset // ignore: cast_nullable_to_non_nullable
as int,selectionBase: null == selectionBase ? _self.selectionBase : selectionBase // ignore: cast_nullable_to_non_nullable
as int,selectionExtent: null == selectionExtent ? _self.selectionExtent : selectionExtent // ignore: cast_nullable_to_non_nullable
as int,scrollOffset: null == scrollOffset ? _self.scrollOffset : scrollOffset // ignore: cast_nullable_to_non_nullable
as double,pipelineCache: freezed == pipelineCache ? _self.pipelineCache : pipelineCache // ignore: cast_nullable_to_non_nullable
as WorkspacePipelineCache?,nirArtifactCache: freezed == nirArtifactCache ? _self.nirArtifactCache : nirArtifactCache // ignore: cast_nullable_to_non_nullable
as WorkspaceNirArtifactCache?,pipelineState: freezed == pipelineState ? _self.pipelineState : pipelineState // ignore: cast_nullable_to_non_nullable
as PipelineState?,canonicalDocument: freezed == canonicalDocument ? _self.canonicalDocument : canonicalDocument // ignore: cast_nullable_to_non_nullable
as CanonicalEditorDocument?,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of WorkspaceFile
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspacePipelineCacheCopyWith<$Res>? get pipelineCache {
    if (_self.pipelineCache == null) {
    return null;
  }

  return $WorkspacePipelineCacheCopyWith<$Res>(_self.pipelineCache!, (value) {
    return _then(_self.copyWith(pipelineCache: value));
  });
}/// Create a copy of WorkspaceFile
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceNirArtifactCacheCopyWith<$Res>? get nirArtifactCache {
    if (_self.nirArtifactCache == null) {
    return null;
  }

  return $WorkspaceNirArtifactCacheCopyWith<$Res>(_self.nirArtifactCache!, (value) {
    return _then(_self.copyWith(nirArtifactCache: value));
  });
}/// Create a copy of WorkspaceFile
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PipelineStateCopyWith<$Res>? get pipelineState {
    if (_self.pipelineState == null) {
    return null;
  }

  return $PipelineStateCopyWith<$Res>(_self.pipelineState!, (value) {
    return _then(_self.copyWith(pipelineState: value));
  });
}
}


/// @nodoc
mixin _$ValidationFocus {

 String get section; String? get itemId;
/// Create a copy of ValidationFocus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ValidationFocusCopyWith<ValidationFocus> get copyWith => _$ValidationFocusCopyWithImpl<ValidationFocus>(this as ValidationFocus, _$identity);

  /// Serializes this ValidationFocus to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ValidationFocus&&(identical(other.section, section) || other.section == section)&&(identical(other.itemId, itemId) || other.itemId == itemId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,section,itemId);

@override
String toString() {
  return 'ValidationFocus(section: $section, itemId: $itemId)';
}


}

/// @nodoc
abstract mixin class $ValidationFocusCopyWith<$Res>  {
  factory $ValidationFocusCopyWith(ValidationFocus value, $Res Function(ValidationFocus) _then) = _$ValidationFocusCopyWithImpl;
@useResult
$Res call({
 String section, String? itemId
});




}
/// @nodoc
class _$ValidationFocusCopyWithImpl<$Res>
    implements $ValidationFocusCopyWith<$Res> {
  _$ValidationFocusCopyWithImpl(this._self, this._then);

  final ValidationFocus _self;
  final $Res Function(ValidationFocus) _then;

/// Create a copy of ValidationFocus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? section = null,Object? itemId = freezed,}) {
  return _then(_self.copyWith(
section: null == section ? _self.section : section // ignore: cast_nullable_to_non_nullable
as String,itemId: freezed == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ValidationFocus].
extension ValidationFocusPatterns on ValidationFocus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ValidationFocus value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ValidationFocus() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ValidationFocus value)  $default,){
final _that = this;
switch (_that) {
case _ValidationFocus():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ValidationFocus value)?  $default,){
final _that = this;
switch (_that) {
case _ValidationFocus() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String section,  String? itemId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ValidationFocus() when $default != null:
return $default(_that.section,_that.itemId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String section,  String? itemId)  $default,) {final _that = this;
switch (_that) {
case _ValidationFocus():
return $default(_that.section,_that.itemId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String section,  String? itemId)?  $default,) {final _that = this;
switch (_that) {
case _ValidationFocus() when $default != null:
return $default(_that.section,_that.itemId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ValidationFocus implements ValidationFocus {
  const _ValidationFocus({this.section = 'overall', this.itemId});
  factory _ValidationFocus.fromJson(Map<String, dynamic> json) => _$ValidationFocusFromJson(json);

@override@JsonKey() final  String section;
@override final  String? itemId;

/// Create a copy of ValidationFocus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ValidationFocusCopyWith<_ValidationFocus> get copyWith => __$ValidationFocusCopyWithImpl<_ValidationFocus>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ValidationFocusToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ValidationFocus&&(identical(other.section, section) || other.section == section)&&(identical(other.itemId, itemId) || other.itemId == itemId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,section,itemId);

@override
String toString() {
  return 'ValidationFocus(section: $section, itemId: $itemId)';
}


}

/// @nodoc
abstract mixin class _$ValidationFocusCopyWith<$Res> implements $ValidationFocusCopyWith<$Res> {
  factory _$ValidationFocusCopyWith(_ValidationFocus value, $Res Function(_ValidationFocus) _then) = __$ValidationFocusCopyWithImpl;
@override @useResult
$Res call({
 String section, String? itemId
});




}
/// @nodoc
class __$ValidationFocusCopyWithImpl<$Res>
    implements _$ValidationFocusCopyWith<$Res> {
  __$ValidationFocusCopyWithImpl(this._self, this._then);

  final _ValidationFocus _self;
  final $Res Function(_ValidationFocus) _then;

/// Create a copy of ValidationFocus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? section = null,Object? itemId = freezed,}) {
  return _then(_ValidationFocus(
section: null == section ? _self.section : section // ignore: cast_nullable_to_non_nullable
as String,itemId: freezed == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$WorkspaceState {

 List<WorkspaceFile> get files; String get activeFileId; String get workspaceName; String? get workspaceSourceKind; String get activePanel; String get activePipelineStep; String? get selectedBenchmarkId; String? get selectedBenchmarkName; String? get selectedDataset; String? get selectedDatasetPath; List<String> get selectedPlatforms; String get selectedDeployTarget; Map<String, dynamic> get benchmarkResultSummary; ValidationFocus? get validationFocus; double get splitRatio; List<WorkspaceActivity> get recentActivities;// Absolute path of the last `.nmtk` file this
// workspace was opened from or saved to, used by autosave to write
// through to that file. Deliberately excluded from the saved JSON
// payload itself — it's local-machine state, not portable workspace
// content, and must not get restored as a stale path when the same
// workspace is opened on a different machine or from a Hub asset.
@JsonKey(includeToJson: false, includeFromJson: false) String? get workspaceFilePath;
/// Create a copy of WorkspaceState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceStateCopyWith<WorkspaceState> get copyWith => _$WorkspaceStateCopyWithImpl<WorkspaceState>(this as WorkspaceState, _$identity);

  /// Serializes this WorkspaceState to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceState&&const DeepCollectionEquality().equals(other.files, files)&&(identical(other.activeFileId, activeFileId) || other.activeFileId == activeFileId)&&(identical(other.workspaceName, workspaceName) || other.workspaceName == workspaceName)&&(identical(other.workspaceSourceKind, workspaceSourceKind) || other.workspaceSourceKind == workspaceSourceKind)&&(identical(other.activePanel, activePanel) || other.activePanel == activePanel)&&(identical(other.activePipelineStep, activePipelineStep) || other.activePipelineStep == activePipelineStep)&&(identical(other.selectedBenchmarkId, selectedBenchmarkId) || other.selectedBenchmarkId == selectedBenchmarkId)&&(identical(other.selectedBenchmarkName, selectedBenchmarkName) || other.selectedBenchmarkName == selectedBenchmarkName)&&(identical(other.selectedDataset, selectedDataset) || other.selectedDataset == selectedDataset)&&(identical(other.selectedDatasetPath, selectedDatasetPath) || other.selectedDatasetPath == selectedDatasetPath)&&const DeepCollectionEquality().equals(other.selectedPlatforms, selectedPlatforms)&&(identical(other.selectedDeployTarget, selectedDeployTarget) || other.selectedDeployTarget == selectedDeployTarget)&&const DeepCollectionEquality().equals(other.benchmarkResultSummary, benchmarkResultSummary)&&(identical(other.validationFocus, validationFocus) || other.validationFocus == validationFocus)&&(identical(other.splitRatio, splitRatio) || other.splitRatio == splitRatio)&&const DeepCollectionEquality().equals(other.recentActivities, recentActivities)&&(identical(other.workspaceFilePath, workspaceFilePath) || other.workspaceFilePath == workspaceFilePath));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(files),activeFileId,workspaceName,workspaceSourceKind,activePanel,activePipelineStep,selectedBenchmarkId,selectedBenchmarkName,selectedDataset,selectedDatasetPath,const DeepCollectionEquality().hash(selectedPlatforms),selectedDeployTarget,const DeepCollectionEquality().hash(benchmarkResultSummary),validationFocus,splitRatio,const DeepCollectionEquality().hash(recentActivities),workspaceFilePath);

@override
String toString() {
  return 'WorkspaceState(files: $files, activeFileId: $activeFileId, workspaceName: $workspaceName, workspaceSourceKind: $workspaceSourceKind, activePanel: $activePanel, activePipelineStep: $activePipelineStep, selectedBenchmarkId: $selectedBenchmarkId, selectedBenchmarkName: $selectedBenchmarkName, selectedDataset: $selectedDataset, selectedDatasetPath: $selectedDatasetPath, selectedPlatforms: $selectedPlatforms, selectedDeployTarget: $selectedDeployTarget, benchmarkResultSummary: $benchmarkResultSummary, validationFocus: $validationFocus, splitRatio: $splitRatio, recentActivities: $recentActivities, workspaceFilePath: $workspaceFilePath)';
}


}

/// @nodoc
abstract mixin class $WorkspaceStateCopyWith<$Res>  {
  factory $WorkspaceStateCopyWith(WorkspaceState value, $Res Function(WorkspaceState) _then) = _$WorkspaceStateCopyWithImpl;
@useResult
$Res call({
 List<WorkspaceFile> files, String activeFileId, String workspaceName, String? workspaceSourceKind, String activePanel, String activePipelineStep, String? selectedBenchmarkId, String? selectedBenchmarkName, String? selectedDataset, String? selectedDatasetPath, List<String> selectedPlatforms, String selectedDeployTarget, Map<String, dynamic> benchmarkResultSummary, ValidationFocus? validationFocus, double splitRatio, List<WorkspaceActivity> recentActivities,@JsonKey(includeToJson: false, includeFromJson: false) String? workspaceFilePath
});


$ValidationFocusCopyWith<$Res>? get validationFocus;

}
/// @nodoc
class _$WorkspaceStateCopyWithImpl<$Res>
    implements $WorkspaceStateCopyWith<$Res> {
  _$WorkspaceStateCopyWithImpl(this._self, this._then);

  final WorkspaceState _self;
  final $Res Function(WorkspaceState) _then;

/// Create a copy of WorkspaceState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? files = null,Object? activeFileId = null,Object? workspaceName = null,Object? workspaceSourceKind = freezed,Object? activePanel = null,Object? activePipelineStep = null,Object? selectedBenchmarkId = freezed,Object? selectedBenchmarkName = freezed,Object? selectedDataset = freezed,Object? selectedDatasetPath = freezed,Object? selectedPlatforms = null,Object? selectedDeployTarget = null,Object? benchmarkResultSummary = null,Object? validationFocus = freezed,Object? splitRatio = null,Object? recentActivities = null,Object? workspaceFilePath = freezed,}) {
  return _then(_self.copyWith(
files: null == files ? _self.files : files // ignore: cast_nullable_to_non_nullable
as List<WorkspaceFile>,activeFileId: null == activeFileId ? _self.activeFileId : activeFileId // ignore: cast_nullable_to_non_nullable
as String,workspaceName: null == workspaceName ? _self.workspaceName : workspaceName // ignore: cast_nullable_to_non_nullable
as String,workspaceSourceKind: freezed == workspaceSourceKind ? _self.workspaceSourceKind : workspaceSourceKind // ignore: cast_nullable_to_non_nullable
as String?,activePanel: null == activePanel ? _self.activePanel : activePanel // ignore: cast_nullable_to_non_nullable
as String,activePipelineStep: null == activePipelineStep ? _self.activePipelineStep : activePipelineStep // ignore: cast_nullable_to_non_nullable
as String,selectedBenchmarkId: freezed == selectedBenchmarkId ? _self.selectedBenchmarkId : selectedBenchmarkId // ignore: cast_nullable_to_non_nullable
as String?,selectedBenchmarkName: freezed == selectedBenchmarkName ? _self.selectedBenchmarkName : selectedBenchmarkName // ignore: cast_nullable_to_non_nullable
as String?,selectedDataset: freezed == selectedDataset ? _self.selectedDataset : selectedDataset // ignore: cast_nullable_to_non_nullable
as String?,selectedDatasetPath: freezed == selectedDatasetPath ? _self.selectedDatasetPath : selectedDatasetPath // ignore: cast_nullable_to_non_nullable
as String?,selectedPlatforms: null == selectedPlatforms ? _self.selectedPlatforms : selectedPlatforms // ignore: cast_nullable_to_non_nullable
as List<String>,selectedDeployTarget: null == selectedDeployTarget ? _self.selectedDeployTarget : selectedDeployTarget // ignore: cast_nullable_to_non_nullable
as String,benchmarkResultSummary: null == benchmarkResultSummary ? _self.benchmarkResultSummary : benchmarkResultSummary // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,validationFocus: freezed == validationFocus ? _self.validationFocus : validationFocus // ignore: cast_nullable_to_non_nullable
as ValidationFocus?,splitRatio: null == splitRatio ? _self.splitRatio : splitRatio // ignore: cast_nullable_to_non_nullable
as double,recentActivities: null == recentActivities ? _self.recentActivities : recentActivities // ignore: cast_nullable_to_non_nullable
as List<WorkspaceActivity>,workspaceFilePath: freezed == workspaceFilePath ? _self.workspaceFilePath : workspaceFilePath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of WorkspaceState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ValidationFocusCopyWith<$Res>? get validationFocus {
    if (_self.validationFocus == null) {
    return null;
  }

  return $ValidationFocusCopyWith<$Res>(_self.validationFocus!, (value) {
    return _then(_self.copyWith(validationFocus: value));
  });
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<WorkspaceFile> files,  String activeFileId,  String workspaceName,  String? workspaceSourceKind,  String activePanel,  String activePipelineStep,  String? selectedBenchmarkId,  String? selectedBenchmarkName,  String? selectedDataset,  String? selectedDatasetPath,  List<String> selectedPlatforms,  String selectedDeployTarget,  Map<String, dynamic> benchmarkResultSummary,  ValidationFocus? validationFocus,  double splitRatio,  List<WorkspaceActivity> recentActivities, @JsonKey(includeToJson: false, includeFromJson: false)  String? workspaceFilePath)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkspaceState() when $default != null:
return $default(_that.files,_that.activeFileId,_that.workspaceName,_that.workspaceSourceKind,_that.activePanel,_that.activePipelineStep,_that.selectedBenchmarkId,_that.selectedBenchmarkName,_that.selectedDataset,_that.selectedDatasetPath,_that.selectedPlatforms,_that.selectedDeployTarget,_that.benchmarkResultSummary,_that.validationFocus,_that.splitRatio,_that.recentActivities,_that.workspaceFilePath);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<WorkspaceFile> files,  String activeFileId,  String workspaceName,  String? workspaceSourceKind,  String activePanel,  String activePipelineStep,  String? selectedBenchmarkId,  String? selectedBenchmarkName,  String? selectedDataset,  String? selectedDatasetPath,  List<String> selectedPlatforms,  String selectedDeployTarget,  Map<String, dynamic> benchmarkResultSummary,  ValidationFocus? validationFocus,  double splitRatio,  List<WorkspaceActivity> recentActivities, @JsonKey(includeToJson: false, includeFromJson: false)  String? workspaceFilePath)  $default,) {final _that = this;
switch (_that) {
case _WorkspaceState():
return $default(_that.files,_that.activeFileId,_that.workspaceName,_that.workspaceSourceKind,_that.activePanel,_that.activePipelineStep,_that.selectedBenchmarkId,_that.selectedBenchmarkName,_that.selectedDataset,_that.selectedDatasetPath,_that.selectedPlatforms,_that.selectedDeployTarget,_that.benchmarkResultSummary,_that.validationFocus,_that.splitRatio,_that.recentActivities,_that.workspaceFilePath);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<WorkspaceFile> files,  String activeFileId,  String workspaceName,  String? workspaceSourceKind,  String activePanel,  String activePipelineStep,  String? selectedBenchmarkId,  String? selectedBenchmarkName,  String? selectedDataset,  String? selectedDatasetPath,  List<String> selectedPlatforms,  String selectedDeployTarget,  Map<String, dynamic> benchmarkResultSummary,  ValidationFocus? validationFocus,  double splitRatio,  List<WorkspaceActivity> recentActivities, @JsonKey(includeToJson: false, includeFromJson: false)  String? workspaceFilePath)?  $default,) {final _that = this;
switch (_that) {
case _WorkspaceState() when $default != null:
return $default(_that.files,_that.activeFileId,_that.workspaceName,_that.workspaceSourceKind,_that.activePanel,_that.activePipelineStep,_that.selectedBenchmarkId,_that.selectedBenchmarkName,_that.selectedDataset,_that.selectedDatasetPath,_that.selectedPlatforms,_that.selectedDeployTarget,_that.benchmarkResultSummary,_that.validationFocus,_that.splitRatio,_that.recentActivities,_that.workspaceFilePath);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WorkspaceState extends WorkspaceState {
  const _WorkspaceState({final  List<WorkspaceFile> files = const [], this.activeFileId = '', this.workspaceName = 'Untitled Workspace', this.workspaceSourceKind, this.activePanel = 'validation', this.activePipelineStep = 'selectData', this.selectedBenchmarkId, this.selectedBenchmarkName, this.selectedDataset, this.selectedDatasetPath, final  List<String> selectedPlatforms = const [], this.selectedDeployTarget = 'sc_neurocore_fpga', final  Map<String, dynamic> benchmarkResultSummary = const {}, this.validationFocus, this.splitRatio = 0.5, final  List<WorkspaceActivity> recentActivities = const [], @JsonKey(includeToJson: false, includeFromJson: false) this.workspaceFilePath}): _files = files,_selectedPlatforms = selectedPlatforms,_benchmarkResultSummary = benchmarkResultSummary,_recentActivities = recentActivities,super._();
  factory _WorkspaceState.fromJson(Map<String, dynamic> json) => _$WorkspaceStateFromJson(json);

 final  List<WorkspaceFile> _files;
@override@JsonKey() List<WorkspaceFile> get files {
  if (_files is EqualUnmodifiableListView) return _files;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_files);
}

@override@JsonKey() final  String activeFileId;
@override@JsonKey() final  String workspaceName;
@override final  String? workspaceSourceKind;
@override@JsonKey() final  String activePanel;
@override@JsonKey() final  String activePipelineStep;
@override final  String? selectedBenchmarkId;
@override final  String? selectedBenchmarkName;
@override final  String? selectedDataset;
@override final  String? selectedDatasetPath;
 final  List<String> _selectedPlatforms;
@override@JsonKey() List<String> get selectedPlatforms {
  if (_selectedPlatforms is EqualUnmodifiableListView) return _selectedPlatforms;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_selectedPlatforms);
}

@override@JsonKey() final  String selectedDeployTarget;
 final  Map<String, dynamic> _benchmarkResultSummary;
@override@JsonKey() Map<String, dynamic> get benchmarkResultSummary {
  if (_benchmarkResultSummary is EqualUnmodifiableMapView) return _benchmarkResultSummary;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_benchmarkResultSummary);
}

@override final  ValidationFocus? validationFocus;
@override@JsonKey() final  double splitRatio;
 final  List<WorkspaceActivity> _recentActivities;
@override@JsonKey() List<WorkspaceActivity> get recentActivities {
  if (_recentActivities is EqualUnmodifiableListView) return _recentActivities;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_recentActivities);
}

// Absolute path of the last `.nmtk` file this
// workspace was opened from or saved to, used by autosave to write
// through to that file. Deliberately excluded from the saved JSON
// payload itself — it's local-machine state, not portable workspace
// content, and must not get restored as a stale path when the same
// workspace is opened on a different machine or from a Hub asset.
@override@JsonKey(includeToJson: false, includeFromJson: false) final  String? workspaceFilePath;

/// Create a copy of WorkspaceState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkspaceStateCopyWith<_WorkspaceState> get copyWith => __$WorkspaceStateCopyWithImpl<_WorkspaceState>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WorkspaceStateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkspaceState&&const DeepCollectionEquality().equals(other._files, _files)&&(identical(other.activeFileId, activeFileId) || other.activeFileId == activeFileId)&&(identical(other.workspaceName, workspaceName) || other.workspaceName == workspaceName)&&(identical(other.workspaceSourceKind, workspaceSourceKind) || other.workspaceSourceKind == workspaceSourceKind)&&(identical(other.activePanel, activePanel) || other.activePanel == activePanel)&&(identical(other.activePipelineStep, activePipelineStep) || other.activePipelineStep == activePipelineStep)&&(identical(other.selectedBenchmarkId, selectedBenchmarkId) || other.selectedBenchmarkId == selectedBenchmarkId)&&(identical(other.selectedBenchmarkName, selectedBenchmarkName) || other.selectedBenchmarkName == selectedBenchmarkName)&&(identical(other.selectedDataset, selectedDataset) || other.selectedDataset == selectedDataset)&&(identical(other.selectedDatasetPath, selectedDatasetPath) || other.selectedDatasetPath == selectedDatasetPath)&&const DeepCollectionEquality().equals(other._selectedPlatforms, _selectedPlatforms)&&(identical(other.selectedDeployTarget, selectedDeployTarget) || other.selectedDeployTarget == selectedDeployTarget)&&const DeepCollectionEquality().equals(other._benchmarkResultSummary, _benchmarkResultSummary)&&(identical(other.validationFocus, validationFocus) || other.validationFocus == validationFocus)&&(identical(other.splitRatio, splitRatio) || other.splitRatio == splitRatio)&&const DeepCollectionEquality().equals(other._recentActivities, _recentActivities)&&(identical(other.workspaceFilePath, workspaceFilePath) || other.workspaceFilePath == workspaceFilePath));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_files),activeFileId,workspaceName,workspaceSourceKind,activePanel,activePipelineStep,selectedBenchmarkId,selectedBenchmarkName,selectedDataset,selectedDatasetPath,const DeepCollectionEquality().hash(_selectedPlatforms),selectedDeployTarget,const DeepCollectionEquality().hash(_benchmarkResultSummary),validationFocus,splitRatio,const DeepCollectionEquality().hash(_recentActivities),workspaceFilePath);

@override
String toString() {
  return 'WorkspaceState(files: $files, activeFileId: $activeFileId, workspaceName: $workspaceName, workspaceSourceKind: $workspaceSourceKind, activePanel: $activePanel, activePipelineStep: $activePipelineStep, selectedBenchmarkId: $selectedBenchmarkId, selectedBenchmarkName: $selectedBenchmarkName, selectedDataset: $selectedDataset, selectedDatasetPath: $selectedDatasetPath, selectedPlatforms: $selectedPlatforms, selectedDeployTarget: $selectedDeployTarget, benchmarkResultSummary: $benchmarkResultSummary, validationFocus: $validationFocus, splitRatio: $splitRatio, recentActivities: $recentActivities, workspaceFilePath: $workspaceFilePath)';
}


}

/// @nodoc
abstract mixin class _$WorkspaceStateCopyWith<$Res> implements $WorkspaceStateCopyWith<$Res> {
  factory _$WorkspaceStateCopyWith(_WorkspaceState value, $Res Function(_WorkspaceState) _then) = __$WorkspaceStateCopyWithImpl;
@override @useResult
$Res call({
 List<WorkspaceFile> files, String activeFileId, String workspaceName, String? workspaceSourceKind, String activePanel, String activePipelineStep, String? selectedBenchmarkId, String? selectedBenchmarkName, String? selectedDataset, String? selectedDatasetPath, List<String> selectedPlatforms, String selectedDeployTarget, Map<String, dynamic> benchmarkResultSummary, ValidationFocus? validationFocus, double splitRatio, List<WorkspaceActivity> recentActivities,@JsonKey(includeToJson: false, includeFromJson: false) String? workspaceFilePath
});


@override $ValidationFocusCopyWith<$Res>? get validationFocus;

}
/// @nodoc
class __$WorkspaceStateCopyWithImpl<$Res>
    implements _$WorkspaceStateCopyWith<$Res> {
  __$WorkspaceStateCopyWithImpl(this._self, this._then);

  final _WorkspaceState _self;
  final $Res Function(_WorkspaceState) _then;

/// Create a copy of WorkspaceState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? files = null,Object? activeFileId = null,Object? workspaceName = null,Object? workspaceSourceKind = freezed,Object? activePanel = null,Object? activePipelineStep = null,Object? selectedBenchmarkId = freezed,Object? selectedBenchmarkName = freezed,Object? selectedDataset = freezed,Object? selectedDatasetPath = freezed,Object? selectedPlatforms = null,Object? selectedDeployTarget = null,Object? benchmarkResultSummary = null,Object? validationFocus = freezed,Object? splitRatio = null,Object? recentActivities = null,Object? workspaceFilePath = freezed,}) {
  return _then(_WorkspaceState(
files: null == files ? _self._files : files // ignore: cast_nullable_to_non_nullable
as List<WorkspaceFile>,activeFileId: null == activeFileId ? _self.activeFileId : activeFileId // ignore: cast_nullable_to_non_nullable
as String,workspaceName: null == workspaceName ? _self.workspaceName : workspaceName // ignore: cast_nullable_to_non_nullable
as String,workspaceSourceKind: freezed == workspaceSourceKind ? _self.workspaceSourceKind : workspaceSourceKind // ignore: cast_nullable_to_non_nullable
as String?,activePanel: null == activePanel ? _self.activePanel : activePanel // ignore: cast_nullable_to_non_nullable
as String,activePipelineStep: null == activePipelineStep ? _self.activePipelineStep : activePipelineStep // ignore: cast_nullable_to_non_nullable
as String,selectedBenchmarkId: freezed == selectedBenchmarkId ? _self.selectedBenchmarkId : selectedBenchmarkId // ignore: cast_nullable_to_non_nullable
as String?,selectedBenchmarkName: freezed == selectedBenchmarkName ? _self.selectedBenchmarkName : selectedBenchmarkName // ignore: cast_nullable_to_non_nullable
as String?,selectedDataset: freezed == selectedDataset ? _self.selectedDataset : selectedDataset // ignore: cast_nullable_to_non_nullable
as String?,selectedDatasetPath: freezed == selectedDatasetPath ? _self.selectedDatasetPath : selectedDatasetPath // ignore: cast_nullable_to_non_nullable
as String?,selectedPlatforms: null == selectedPlatforms ? _self._selectedPlatforms : selectedPlatforms // ignore: cast_nullable_to_non_nullable
as List<String>,selectedDeployTarget: null == selectedDeployTarget ? _self.selectedDeployTarget : selectedDeployTarget // ignore: cast_nullable_to_non_nullable
as String,benchmarkResultSummary: null == benchmarkResultSummary ? _self._benchmarkResultSummary : benchmarkResultSummary // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,validationFocus: freezed == validationFocus ? _self.validationFocus : validationFocus // ignore: cast_nullable_to_non_nullable
as ValidationFocus?,splitRatio: null == splitRatio ? _self.splitRatio : splitRatio // ignore: cast_nullable_to_non_nullable
as double,recentActivities: null == recentActivities ? _self._recentActivities : recentActivities // ignore: cast_nullable_to_non_nullable
as List<WorkspaceActivity>,workspaceFilePath: freezed == workspaceFilePath ? _self.workspaceFilePath : workspaceFilePath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of WorkspaceState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ValidationFocusCopyWith<$Res>? get validationFocus {
    if (_self.validationFocus == null) {
    return null;
  }

  return $ValidationFocusCopyWith<$Res>(_self.validationFocus!, (value) {
    return _then(_self.copyWith(validationFocus: value));
  });
}
}


/// @nodoc
mixin _$WorkspaceActivity {

 String get id; String get kind; String get title; String get detail; String get status; String get timestamp; String? get panelId;
/// Create a copy of WorkspaceActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceActivityCopyWith<WorkspaceActivity> get copyWith => _$WorkspaceActivityCopyWithImpl<WorkspaceActivity>(this as WorkspaceActivity, _$identity);

  /// Serializes this WorkspaceActivity to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceActivity&&(identical(other.id, id) || other.id == id)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.title, title) || other.title == title)&&(identical(other.detail, detail) || other.detail == detail)&&(identical(other.status, status) || other.status == status)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.panelId, panelId) || other.panelId == panelId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,kind,title,detail,status,timestamp,panelId);

@override
String toString() {
  return 'WorkspaceActivity(id: $id, kind: $kind, title: $title, detail: $detail, status: $status, timestamp: $timestamp, panelId: $panelId)';
}


}

/// @nodoc
abstract mixin class $WorkspaceActivityCopyWith<$Res>  {
  factory $WorkspaceActivityCopyWith(WorkspaceActivity value, $Res Function(WorkspaceActivity) _then) = _$WorkspaceActivityCopyWithImpl;
@useResult
$Res call({
 String id, String kind, String title, String detail, String status, String timestamp, String? panelId
});




}
/// @nodoc
class _$WorkspaceActivityCopyWithImpl<$Res>
    implements $WorkspaceActivityCopyWith<$Res> {
  _$WorkspaceActivityCopyWithImpl(this._self, this._then);

  final WorkspaceActivity _self;
  final $Res Function(WorkspaceActivity) _then;

/// Create a copy of WorkspaceActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? kind = null,Object? title = null,Object? detail = null,Object? status = null,Object? timestamp = null,Object? panelId = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as String,panelId: freezed == panelId ? _self.panelId : panelId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkspaceActivity].
extension WorkspaceActivityPatterns on WorkspaceActivity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkspaceActivity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkspaceActivity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkspaceActivity value)  $default,){
final _that = this;
switch (_that) {
case _WorkspaceActivity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkspaceActivity value)?  $default,){
final _that = this;
switch (_that) {
case _WorkspaceActivity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String kind,  String title,  String detail,  String status,  String timestamp,  String? panelId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkspaceActivity() when $default != null:
return $default(_that.id,_that.kind,_that.title,_that.detail,_that.status,_that.timestamp,_that.panelId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String kind,  String title,  String detail,  String status,  String timestamp,  String? panelId)  $default,) {final _that = this;
switch (_that) {
case _WorkspaceActivity():
return $default(_that.id,_that.kind,_that.title,_that.detail,_that.status,_that.timestamp,_that.panelId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String kind,  String title,  String detail,  String status,  String timestamp,  String? panelId)?  $default,) {final _that = this;
switch (_that) {
case _WorkspaceActivity() when $default != null:
return $default(_that.id,_that.kind,_that.title,_that.detail,_that.status,_that.timestamp,_that.panelId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WorkspaceActivity implements WorkspaceActivity {
  const _WorkspaceActivity({this.id = '', this.kind = 'activity', this.title = 'Workspace activity', this.detail = '', this.status = 'info', this.timestamp = '', this.panelId});
  factory _WorkspaceActivity.fromJson(Map<String, dynamic> json) => _$WorkspaceActivityFromJson(json);

@override@JsonKey() final  String id;
@override@JsonKey() final  String kind;
@override@JsonKey() final  String title;
@override@JsonKey() final  String detail;
@override@JsonKey() final  String status;
@override@JsonKey() final  String timestamp;
@override final  String? panelId;

/// Create a copy of WorkspaceActivity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkspaceActivityCopyWith<_WorkspaceActivity> get copyWith => __$WorkspaceActivityCopyWithImpl<_WorkspaceActivity>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WorkspaceActivityToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkspaceActivity&&(identical(other.id, id) || other.id == id)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.title, title) || other.title == title)&&(identical(other.detail, detail) || other.detail == detail)&&(identical(other.status, status) || other.status == status)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.panelId, panelId) || other.panelId == panelId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,kind,title,detail,status,timestamp,panelId);

@override
String toString() {
  return 'WorkspaceActivity(id: $id, kind: $kind, title: $title, detail: $detail, status: $status, timestamp: $timestamp, panelId: $panelId)';
}


}

/// @nodoc
abstract mixin class _$WorkspaceActivityCopyWith<$Res> implements $WorkspaceActivityCopyWith<$Res> {
  factory _$WorkspaceActivityCopyWith(_WorkspaceActivity value, $Res Function(_WorkspaceActivity) _then) = __$WorkspaceActivityCopyWithImpl;
@override @useResult
$Res call({
 String id, String kind, String title, String detail, String status, String timestamp, String? panelId
});




}
/// @nodoc
class __$WorkspaceActivityCopyWithImpl<$Res>
    implements _$WorkspaceActivityCopyWith<$Res> {
  __$WorkspaceActivityCopyWithImpl(this._self, this._then);

  final _WorkspaceActivity _self;
  final $Res Function(_WorkspaceActivity) _then;

/// Create a copy of WorkspaceActivity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? kind = null,Object? title = null,Object? detail = null,Object? status = null,Object? timestamp = null,Object? panelId = freezed,}) {
  return _then(_WorkspaceActivity(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as String,panelId: freezed == panelId ? _self.panelId : panelId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
