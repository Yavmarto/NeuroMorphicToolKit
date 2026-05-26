import 'package:flutter/widgets.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
// Legacy shell adapter imports (kept for backward-compat with /workspace?moduleId= route)
import 'package:neurocnl_studio/shell_adapter.dart';
import 'package:neurohub_shell_adapter/neurohub_shell_adapter.dart';
// import 'package:neurochip/shell_adapter.dart';
import 'package:neurobench_frontend/shell_adapter.dart';

typedef NativeSurfaceBuilder = Widget Function(WorkspaceSession session);

class NativeSurfaceRegistry {
  static final Map<String, NativeSurfaceBuilder> _builders =
      <String, NativeSurfaceBuilder>{
    'neurocnl': (WorkspaceSession session) {
      return NeurocnlShellAdapter(
        initialLocation: session.deepLink ?? '/',
      );
    },
    'Neurohub': (WorkspaceSession session) {
      return NeurohubShellAdapter(
        initialLocation: session.deepLink ?? '/',
      );
    },
    'Neurochip': (WorkspaceSession session) {
      return NeurocnlShellAdapter(
        initialLocation: session.deepLink ?? '/?panel=deploy',
        initialRestoreState: session.restoreState.isEmpty
            ? const <String, Object?>{}
            : session.restoreState,
      );
    },
    'Neurobench': (WorkspaceSession session) {
      return NeurobenchShellAdapter(
        initialLocation: session.deepLink ?? '/',
      );
    },
  };

  static bool supportsModule(String moduleId) =>
      _builders.containsKey(moduleId);

  static Widget build(String moduleId, WorkspaceSession session) {
    final builder = _builders[moduleId];
    if (builder == null) {
      throw ArgumentError('No native surface registered for $moduleId');
    }
    return builder(session);
  }
}
