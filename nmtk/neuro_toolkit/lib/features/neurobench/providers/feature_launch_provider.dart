import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

/// The root-owned connection available to every NeuroBench service.
///
/// This provider is overridden by [NeurobenchShellAdapter]. Keeping it
/// scoped to the feature prevents NeuroBench from selecting or persisting a
/// competing backend.
final featureLaunchContextProvider = Provider<NmtkFeatureLaunchContext>(
  (ref) => NmtkFeatureLaunchContext(
    moduleId: NmtkModuleId.neurobench,
    backendUri: Uri.parse('http://invalid-root-context'),
    onNavigate: (_) async => false,
    onReportError: (_) async {},
    onEditServer: () async {},
  ),
);
