// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'module_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ModuleState {

 List<Module> get modules; List<String> get activeModuleIds; bool get pythonAvailable; bool get mujocoAvailable; LauncherUpdate? get pendingLauncherUpdate;
/// Create a copy of ModuleState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModuleStateCopyWith<ModuleState> get copyWith => _$ModuleStateCopyWithImpl<ModuleState>(this as ModuleState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModuleState&&const DeepCollectionEquality().equals(other.modules, modules)&&const DeepCollectionEquality().equals(other.activeModuleIds, activeModuleIds)&&(identical(other.pythonAvailable, pythonAvailable) || other.pythonAvailable == pythonAvailable)&&(identical(other.mujocoAvailable, mujocoAvailable) || other.mujocoAvailable == mujocoAvailable)&&(identical(other.pendingLauncherUpdate, pendingLauncherUpdate) || other.pendingLauncherUpdate == pendingLauncherUpdate));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(modules),const DeepCollectionEquality().hash(activeModuleIds),pythonAvailable,mujocoAvailable,pendingLauncherUpdate);

@override
String toString() {
  return 'ModuleState(modules: $modules, activeModuleIds: $activeModuleIds, pythonAvailable: $pythonAvailable, mujocoAvailable: $mujocoAvailable, pendingLauncherUpdate: $pendingLauncherUpdate)';
}


}

/// @nodoc
abstract mixin class $ModuleStateCopyWith<$Res>  {
  factory $ModuleStateCopyWith(ModuleState value, $Res Function(ModuleState) _then) = _$ModuleStateCopyWithImpl;
@useResult
$Res call({
 List<Module> modules, List<String> activeModuleIds, bool pythonAvailable, bool mujocoAvailable, LauncherUpdate? pendingLauncherUpdate
});




}
/// @nodoc
class _$ModuleStateCopyWithImpl<$Res>
    implements $ModuleStateCopyWith<$Res> {
  _$ModuleStateCopyWithImpl(this._self, this._then);

  final ModuleState _self;
  final $Res Function(ModuleState) _then;

/// Create a copy of ModuleState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modules = null,Object? activeModuleIds = null,Object? pythonAvailable = null,Object? mujocoAvailable = null,Object? pendingLauncherUpdate = freezed,}) {
  return _then(_self.copyWith(
modules: null == modules ? _self.modules : modules // ignore: cast_nullable_to_non_nullable
as List<Module>,activeModuleIds: null == activeModuleIds ? _self.activeModuleIds : activeModuleIds // ignore: cast_nullable_to_non_nullable
as List<String>,pythonAvailable: null == pythonAvailable ? _self.pythonAvailable : pythonAvailable // ignore: cast_nullable_to_non_nullable
as bool,mujocoAvailable: null == mujocoAvailable ? _self.mujocoAvailable : mujocoAvailable // ignore: cast_nullable_to_non_nullable
as bool,pendingLauncherUpdate: freezed == pendingLauncherUpdate ? _self.pendingLauncherUpdate : pendingLauncherUpdate // ignore: cast_nullable_to_non_nullable
as LauncherUpdate?,
  ));
}

}


/// Adds pattern-matching-related methods to [ModuleState].
extension ModuleStatePatterns on ModuleState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModuleState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModuleState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModuleState value)  $default,){
final _that = this;
switch (_that) {
case _ModuleState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModuleState value)?  $default,){
final _that = this;
switch (_that) {
case _ModuleState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<Module> modules,  List<String> activeModuleIds,  bool pythonAvailable,  bool mujocoAvailable,  LauncherUpdate? pendingLauncherUpdate)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModuleState() when $default != null:
return $default(_that.modules,_that.activeModuleIds,_that.pythonAvailable,_that.mujocoAvailable,_that.pendingLauncherUpdate);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<Module> modules,  List<String> activeModuleIds,  bool pythonAvailable,  bool mujocoAvailable,  LauncherUpdate? pendingLauncherUpdate)  $default,) {final _that = this;
switch (_that) {
case _ModuleState():
return $default(_that.modules,_that.activeModuleIds,_that.pythonAvailable,_that.mujocoAvailable,_that.pendingLauncherUpdate);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<Module> modules,  List<String> activeModuleIds,  bool pythonAvailable,  bool mujocoAvailable,  LauncherUpdate? pendingLauncherUpdate)?  $default,) {final _that = this;
switch (_that) {
case _ModuleState() when $default != null:
return $default(_that.modules,_that.activeModuleIds,_that.pythonAvailable,_that.mujocoAvailable,_that.pendingLauncherUpdate);case _:
  return null;

}
}

}

/// @nodoc


class _ModuleState extends ModuleState {
  const _ModuleState({final  List<Module> modules = const [], final  List<String> activeModuleIds = const [], this.pythonAvailable = true, this.mujocoAvailable = true, this.pendingLauncherUpdate}): _modules = modules,_activeModuleIds = activeModuleIds,super._();
  

 final  List<Module> _modules;
@override@JsonKey() List<Module> get modules {
  if (_modules is EqualUnmodifiableListView) return _modules;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_modules);
}

 final  List<String> _activeModuleIds;
@override@JsonKey() List<String> get activeModuleIds {
  if (_activeModuleIds is EqualUnmodifiableListView) return _activeModuleIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_activeModuleIds);
}

@override@JsonKey() final  bool pythonAvailable;
@override@JsonKey() final  bool mujocoAvailable;
@override final  LauncherUpdate? pendingLauncherUpdate;

/// Create a copy of ModuleState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModuleStateCopyWith<_ModuleState> get copyWith => __$ModuleStateCopyWithImpl<_ModuleState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModuleState&&const DeepCollectionEquality().equals(other._modules, _modules)&&const DeepCollectionEquality().equals(other._activeModuleIds, _activeModuleIds)&&(identical(other.pythonAvailable, pythonAvailable) || other.pythonAvailable == pythonAvailable)&&(identical(other.mujocoAvailable, mujocoAvailable) || other.mujocoAvailable == mujocoAvailable)&&(identical(other.pendingLauncherUpdate, pendingLauncherUpdate) || other.pendingLauncherUpdate == pendingLauncherUpdate));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_modules),const DeepCollectionEquality().hash(_activeModuleIds),pythonAvailable,mujocoAvailable,pendingLauncherUpdate);

@override
String toString() {
  return 'ModuleState(modules: $modules, activeModuleIds: $activeModuleIds, pythonAvailable: $pythonAvailable, mujocoAvailable: $mujocoAvailable, pendingLauncherUpdate: $pendingLauncherUpdate)';
}


}

/// @nodoc
abstract mixin class _$ModuleStateCopyWith<$Res> implements $ModuleStateCopyWith<$Res> {
  factory _$ModuleStateCopyWith(_ModuleState value, $Res Function(_ModuleState) _then) = __$ModuleStateCopyWithImpl;
@override @useResult
$Res call({
 List<Module> modules, List<String> activeModuleIds, bool pythonAvailable, bool mujocoAvailable, LauncherUpdate? pendingLauncherUpdate
});




}
/// @nodoc
class __$ModuleStateCopyWithImpl<$Res>
    implements _$ModuleStateCopyWith<$Res> {
  __$ModuleStateCopyWithImpl(this._self, this._then);

  final _ModuleState _self;
  final $Res Function(_ModuleState) _then;

/// Create a copy of ModuleState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modules = null,Object? activeModuleIds = null,Object? pythonAvailable = null,Object? mujocoAvailable = null,Object? pendingLauncherUpdate = freezed,}) {
  return _then(_ModuleState(
modules: null == modules ? _self._modules : modules // ignore: cast_nullable_to_non_nullable
as List<Module>,activeModuleIds: null == activeModuleIds ? _self._activeModuleIds : activeModuleIds // ignore: cast_nullable_to_non_nullable
as List<String>,pythonAvailable: null == pythonAvailable ? _self.pythonAvailable : pythonAvailable // ignore: cast_nullable_to_non_nullable
as bool,mujocoAvailable: null == mujocoAvailable ? _self.mujocoAvailable : mujocoAvailable // ignore: cast_nullable_to_non_nullable
as bool,pendingLauncherUpdate: freezed == pendingLauncherUpdate ? _self.pendingLauncherUpdate : pendingLauncherUpdate // ignore: cast_nullable_to_non_nullable
as LauncherUpdate?,
  ));
}


}

// dart format on
