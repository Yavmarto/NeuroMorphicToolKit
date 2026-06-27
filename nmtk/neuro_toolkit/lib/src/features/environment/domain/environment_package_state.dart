import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:neuro_toolkit/services/environment_api_service.dart';

part 'environment_package_state.freezed.dart';

/// State for the per-environment package list panel.
@freezed
abstract class EnvironmentPackageState with _$EnvironmentPackageState {
  const factory EnvironmentPackageState({
    @Default(false) bool loading,
    @Default([]) List<PackageInfo> packages,
    String? error,
  }) = _EnvironmentPackageState;
}

/// State for the export/requirements dialog.
@freezed
abstract class EnvironmentExportState with _$EnvironmentExportState {
  const factory EnvironmentExportState({
    @Default(true) bool loading,
    @Default('') String body,
    @Default('delta') String mode,
    String? error,
  }) = _EnvironmentExportState;
}
