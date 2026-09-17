import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

class _FeatureLaunchContextNotifier extends Notifier<NmtkFeatureLaunchContext> {
  @override
  NmtkFeatureLaunchContext build() => NmtkFeatureLaunchContext(
    moduleId: NmtkModuleId.neurocnl,
    backendUri: Uri.parse('http://invalid-root-context'),
    onNavigate: (_) async => false,
    onReportError: (_) async {},
    onEditServer: () async {},
  );

  /// Publishes the real, root-owned connection. Called by
  /// [NeurocnlShellAdapter] once it knows the actual launch context.
  void publish(NmtkFeatureLaunchContext value) => state = value;
}

/// The root-owned connection available to every NeuroStudio service.
///
/// [NeurocnlShellAdapter] sets this value in place (via
/// `ref.read(featureLaunchContextProvider.notifier).publish(...)`) rather
/// than overriding it on a nested `ProviderScope`. Many Studio Notifiers
/// read the derived `apiClientProvider` lazily from inside their own
/// methods rather than from `build()`, which does not reliably pick up a
/// dependency overridden only on a child scope — every such Notifier ends
/// up reading this same root-level provider instead, so mutating it
/// directly is what actually reaches all of them.
final featureLaunchContextProvider =
    NotifierProvider<_FeatureLaunchContextNotifier, NmtkFeatureLaunchContext>(
      _FeatureLaunchContextNotifier.new,
    );

/// Test seam: a notifier pre-seeded with [initial], for tests that build
/// Studio surfaces directly (without going through [NeurocnlShellAdapter],
/// which is what normally publishes the real value). Use inline via
/// `featureLaunchContextProvider.overrideWith(() =>
/// SeededFeatureLaunchContextNotifier(myLaunchContext))`.
class SeededFeatureLaunchContextNotifier extends _FeatureLaunchContextNotifier {
  SeededFeatureLaunchContextNotifier(this.initial);

  final NmtkFeatureLaunchContext initial;

  @override
  NmtkFeatureLaunchContext build() => initial;
}
