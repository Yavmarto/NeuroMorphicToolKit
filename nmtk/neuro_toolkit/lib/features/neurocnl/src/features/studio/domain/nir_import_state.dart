import 'dart:convert';
import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/nir_hdf5_tree.dart';

part 'nir_import_state.freezed.dart';
part 'nir_import_state.g.dart';

/// Where the currently displayed NIR tree came from.
enum NirSource { none, pipeline, file, canvas }

@Freezed(unionKey: 'status', fallbackUnion: 'idle')
sealed class NirImportState with _$NirImportState {
  const NirImportState._();

  @FreezedUnionValue('idle')
  const factory NirImportState.idle() = NirImportIdle;

  @FreezedUnionValue('loading')
  const factory NirImportState.loading({
    @Default(NirSource.none) NirSource source,
  }) = NirImportLoading;

  @FreezedUnionValue('loaded')
  const factory NirImportState.loaded({
    @JsonKey(
      fromJson: _nirInspectResultFromJson,
      toJson: _nirInspectResultToJson,
    )
    required NirInspectResult result,
    @Default(NirSource.none) NirSource source,
    @Default(false) bool writeBackConsumed,
    @Uint8ListConverter() Uint8List? rawBytes,
    @Default('') String importId,
  }) = NirImportLoaded;

  @FreezedUnionValue('error')
  const factory NirImportState.error({
    required String error,
    @Default(NirSource.none) NirSource source,
  }) = NirImportError;

  NirSource get source => map(
    idle: (_) => NirSource.none,
    loading: (s) => s.source,
    loaded: (s) => s.source,
    error: (s) => s.source,
  );

  NirInspectResult? get result => mapOrNull(loaded: (s) => s.result);

  String? get error => mapOrNull(error: (s) => s.error);

  bool get writeBackConsumed =>
      mapOrNull(loaded: (s) => s.writeBackConsumed) ?? false;

  Uint8List? get rawBytes => mapOrNull(loaded: (s) => s.rawBytes);

  /// Opaque handle to the real (trained) weight values recovered from a
  /// `.nir` upload via `POST /api/neurosim/nir/import`. Empty when the
  /// current state didn't go through that endpoint (e.g. pipeline-generated
  /// or canvas-exported NIR, or older workflows).
  String get importId => mapOrNull(loaded: (s) => s.importId) ?? '';

  factory NirImportState.fromJson(Map<String, dynamic> json) =>
      _$NirImportStateFromJson(json);
}

class Uint8ListConverter implements JsonConverter<Uint8List?, String?> {
  const Uint8ListConverter();

  @override
  Uint8List? fromJson(String? json) {
    if (json == null) return null;
    return base64Decode(json);
  }

  @override
  String? toJson(Uint8List? object) {
    if (object == null) return null;
    return base64Encode(object);
  }
}

NirInspectResult _nirInspectResultFromJson(Map<String, dynamic> json) =>
    NirInspectResult.fromJson(json);

Map<String, dynamic> _nirInspectResultToJson(NirInspectResult result) =>
    result.toJson();
