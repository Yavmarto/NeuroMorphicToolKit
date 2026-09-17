import 'package:freezed_annotation/freezed_annotation.dart';

part 'python_install_state.freezed.dart';

@freezed
abstract class PythonInstallState with _$PythonInstallState {
  const factory PythonInstallState({
    @Default(false) bool isInstalling,
    @Default(false) bool isChecking,
    String? installOutput,
    String? errorMessage,
  }) = _PythonInstallState;
}
