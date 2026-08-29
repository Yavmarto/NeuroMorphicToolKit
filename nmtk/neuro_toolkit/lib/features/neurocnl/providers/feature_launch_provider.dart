import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

/// The root-owned connection available to every NeuroStudio service.
///
/// This provider is overridden by [NeurocnlShellAdapter].  Keeping it scoped
/// to the feature prevents a Studio workspace from selecting or persisting a
/// competing backend.
final featureLaunchContextProvider = Provider<NmtkFeatureLaunchContext>(
  (ref) => NmtkFeatureLaunchContext(
    moduleId: NmtkModuleId.neurocnl,
    backendUri: Uri.parse('http://invalid-root-context'),
    onNavigate: (_) async => false,
    onReportError: (_) async {},
    onEditServer: () async {},
  ),
);
