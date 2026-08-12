import 'package:flutter/widgets.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
// Native module adapters hosted by the launcher's single workspace surface.
import 'package:neurocnl_studio/shell_adapter.dart';
// import 'package:neurochip/shell_adapter.dart';
import 'package:neurobench_frontend/shell_adapter.dart';

typedef NativeSurfaceBuilder = Widget Function(
  WorkspaceSession session, {
  String? initialServerUrl,
  Widget? workspaceHeaderAction,
  Future<void> Function()? onEditServer,
});

class NativeSurfaceRegistry {
  static final Map<String, NativeSurfaceBuilder> _builders =
      <String, NativeSurfaceBuilder>{
    'neurocnl': (
      WorkspaceSession session, {
      String? initialServerUrl,
      Widget? workspaceHeaderAction,
      Future<void> Function()? onEditServer,
    }) {
      return NeurocnlShellAdapter(
        initialLocation: session.deepLink ?? '/',
        initialServerUrl: initialServerUrl,
        workspaceHeaderAction: workspaceHeaderAction,
        onEditServer: onEditServer,
      );
    },
    'Neurochip': (
      WorkspaceSession session, {
      String? initialServerUrl,
      Widget? workspaceHeaderAction,
      Future<void> Function()? onEditServer,
    }) {
      return NeurocnlShellAdapter(
        initialLocation: session.deepLink ?? '/?panel=deploy',
        initialRestoreState: session.restoreState.isEmpty
            ? const <String, Object?>{}
            : session.restoreState,
        initialServerUrl: initialServerUrl,
        onEditServer: onEditServer,
      );
    },
    'Neurobench': (
      WorkspaceSession session, {
      String? initialServerUrl,
      Widget? workspaceHeaderAction,
      Future<void> Function()? onEditServer,
    }) {
      return NeurobenchShellAdapter(
        initialLocation: session.deepLink ?? '/',
      );
    },
  };

  static bool supportsModule(String moduleId) =>
      _builders.containsKey(moduleId);

  static Widget build(
    String moduleId,
    WorkspaceSession session, {
    String? initialServerUrl,
    Widget? workspaceHeaderAction,
    Future<void> Function()? onEditServer,
  }) {
    final builder = _builders[moduleId];
    if (builder == null) {
      throw ArgumentError('No native surface registered for $moduleId');
    }
    return builder(
      session,
      initialServerUrl: initialServerUrl,
      workspaceHeaderAction: workspaceHeaderAction,
      onEditServer: onEditServer,
    );
  }
}
