// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nir_import_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NirImportIdle _$NirImportIdleFromJson(Map<String, dynamic> json) =>
    NirImportIdle($type: json['status'] as String?);

Map<String, dynamic> _$NirImportIdleToJson(NirImportIdle instance) =>
    <String, dynamic>{'status': instance.$type};

NirImportLoading _$NirImportLoadingFromJson(Map<String, dynamic> json) =>
    NirImportLoading(
      source:
          $enumDecodeNullable(_$NirSourceEnumMap, json['source']) ??
          NirSource.none,
      $type: json['status'] as String?,
    );

Map<String, dynamic> _$NirImportLoadingToJson(NirImportLoading instance) =>
    <String, dynamic>{
      'source': _$NirSourceEnumMap[instance.source]!,
      'status': instance.$type,
    };

const _$NirSourceEnumMap = {
  NirSource.none: 'none',
  NirSource.pipeline: 'pipeline',
  NirSource.file: 'file',
  NirSource.canvas: 'canvas',
};

NirImportLoaded _$NirImportLoadedFromJson(
  Map<String, dynamic> json,
) => NirImportLoaded(
  result: _nirInspectResultFromJson(json['result'] as Map<String, dynamic>),
  source:
      $enumDecodeNullable(_$NirSourceEnumMap, json['source']) ?? NirSource.none,
  writeBackConsumed: json['writeBackConsumed'] as bool? ?? false,
  rawBytes: const Uint8ListConverter().fromJson(json['rawBytes'] as String?),
  importId: json['importId'] as String? ?? '',
  $type: json['status'] as String?,
);

Map<String, dynamic> _$NirImportLoadedToJson(NirImportLoaded instance) =>
    <String, dynamic>{
      'result': _nirInspectResultToJson(instance.result),
      'source': _$NirSourceEnumMap[instance.source]!,
      'writeBackConsumed': instance.writeBackConsumed,
      'rawBytes': const Uint8ListConverter().toJson(instance.rawBytes),
      'importId': instance.importId,
      'status': instance.$type,
    };

NirImportError _$NirImportErrorFromJson(Map<String, dynamic> json) =>
    NirImportError(
      error: json['error'] as String,
      source:
          $enumDecodeNullable(_$NirSourceEnumMap, json['source']) ??
          NirSource.none,
      $type: json['status'] as String?,
    );

Map<String, dynamic> _$NirImportErrorToJson(NirImportError instance) =>
    <String, dynamic>{
      'error': instance.error,
      'source': _$NirSourceEnumMap[instance.source]!,
      'status': instance.$type,
    };
