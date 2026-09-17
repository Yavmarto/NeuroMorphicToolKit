import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';

part 'workspace_state.freezed.dart';

@freezed
abstract class WorkspaceState with _$WorkspaceState {
  const factory WorkspaceState({
    @Default([]) List<WorkspaceSession> sessions,
    String? focusedModuleId,
    @Default(false) bool defaultSessionsEnsured,
  }) = _WorkspaceState;

  const WorkspaceState._();

  bool get hasSessions => sessions.isNotEmpty;
}
