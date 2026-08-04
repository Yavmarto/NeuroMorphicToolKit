import 'package:flutter/widgets.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
// Legacy shell adapter imports (kept for backward-compat with /workspace?moduleId= route)
import 'package:neurocnl_studio/shell_adapter.dart';
import 'package:neurohub_shell_adapter/neurohub_shell_adapter.dart';
// import 'package:neurochip/shell_adapter.dart';
import 'package:neurobench_frontend/shell_adapter.dart';
import 'package:neurosense_shell_adapter/neurosense_shell_adapter.dart';

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
    'Neurohub': (
      WorkspaceSession session, {
      String? initialServerUrl,
      Widget? workspaceHeaderAction,
      Future<void> Function()? onEditServer,
    }) {
      return NeurohubShellAdapter(
        initialLocation: session.deepLink ?? '/',
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
    'Neurosense': (
      WorkspaceSession session, {
      String? initialServerUrl,
      Widget? workspaceHeaderAction,
      Future<void> Function()? onEditServer,
    }) {
      return NeurosenseShellAdapter(
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
