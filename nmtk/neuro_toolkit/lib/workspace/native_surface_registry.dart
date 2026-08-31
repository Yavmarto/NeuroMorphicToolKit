import 'package:flutter/widgets.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
// Native module adapters hosted by the launcher's single workspace surface.
import 'package:neuro_toolkit/features/neurocnl/neurocnl_studio.dart';
// import 'package:neurochip/shell_adapter.dart';
import 'package:neuro_toolkit/features/neurobench/shell_adapter.dart';

typedef NativeSurfaceBuilder =
    Widget Function(NmtkFeatureLaunchContext launchContext);

class NativeSurfaceRegistry {
  static final Map<NmtkModuleId, NativeSurfaceBuilder> _builders =
      <NmtkModuleId, NativeSurfaceBuilder>{
        NmtkModuleId.neurocnl: _buildNeurocnl,
        NmtkModuleId.neurochip: _buildNeurocnl,
        NmtkModuleId.neurobench: _buildNeurobench,
      };

  static bool supportsModule(String moduleId) {
    try {
      return _builders.containsKey(NmtkModuleId.fromExternal(moduleId));
    } on ArgumentError {
      return false;
    }
  }

  static Widget _buildNeurocnl(NmtkFeatureLaunchContext launchContext) {
    return NmtkHostNavigationScope(
      navigator: launchContext.onNavigate,
      child: NeurocnlShellAdapter(launchContext: launchContext),
    );
  }

  static Widget _buildNeurobench(NmtkFeatureLaunchContext launchContext) {
    return NmtkHostNavigationScope(
      navigator: launchContext.onNavigate,
      child: NeurobenchShellAdapter(launchContext: launchContext),
    );
  }

  static Widget build(
    WorkspaceSession session, {
    required NmtkFeatureLaunchContext launchContext,
  }) {
    final sessionModuleId = NmtkModuleId.fromExternal(session.moduleId);
    if (sessionModuleId != launchContext.moduleId) {
      throw ArgumentError(
        'The workspace session and launch context must target the same module.',
      );
    }
    final builder = _builders[sessionModuleId];
    if (builder == null) {
      throw ArgumentError(
        'No native surface registered for ${session.moduleId}',
      );
    }
    return builder(launchContext);
  }
}
