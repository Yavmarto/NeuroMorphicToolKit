import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/app.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/feature_launch_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

const String kTestNeurocnlServerUrl = 'http://127.0.0.1:9000/api/neurocnl';

Future<void> noopEditServer() async {}

Widget buildNeurocnlSurfaceTestHost({
  String initialLocation = '/',
  String initialServerUrl = kTestNeurocnlServerUrl,
  String initialAdminToken = '',
  ThemeMode themeMode = ThemeMode.dark,
}) {
  final launchContext = NmtkFeatureLaunchContext(
    moduleId: NmtkModuleId.neurocnl,
    backendUri: Uri.parse(initialServerUrl),
    authentication: NmtkFeatureAuthentication(adminToken: initialAdminToken),
    onNavigate: (_) async => false,
    onReportError: (_) async {},
    onEditServer: noopEditServer,
  );
  return ProviderScope(
    overrides: [
      featureLaunchContextProvider.overrideWith(
        () => SeededFeatureLaunchContextNotifier(launchContext),
      ),
    ],
    child: _PublishLaunchContext(
      value: launchContext,
      child: NmtkZetaTheme.wrap(
        initialThemeMode: themeMode,
        builder: (context, light, dark, mode) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: light,
          darkTheme: dark,
          themeMode: mode,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: NeurocnlStudioSurface(
            initialLocation: initialLocation,
            onEditServer: noopEditServer,
          ),
        ),
      ),
    ),
  );
}

/// Re-publishes a changed [value] onto the seeded
/// [featureLaunchContextProvider] notifier in place, the same way
/// [NeurocnlShellAdapter] does in production — rather than relying on
/// `ProviderScope.overrides` to propagate a *changed* seed value across a
/// rebuild, which a `NotifierProvider` override does not reliably do (the
/// existing notifier state survives a `ProviderScope` rebuild instead of
/// re-running the override's factory with the new seed).
class _PublishLaunchContext extends ConsumerStatefulWidget {
  const _PublishLaunchContext({required this.value, required this.child});

  final NmtkFeatureLaunchContext value;
  final Widget child;

  @override
  ConsumerState<_PublishLaunchContext> createState() =>
      _PublishLaunchContextState();
}

class _PublishLaunchContextState extends ConsumerState<_PublishLaunchContext> {
  @override
  void didUpdateWidget(_PublishLaunchContext oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value.backendUri != widget.value.backendUri ||
        oldWidget.value.authentication.adminToken !=
            widget.value.authentication.adminToken) {
      // Deferred: Riverpod forbids modifying a provider synchronously from
      // within a widget lifecycle method such as didUpdateWidget.
      final value = widget.value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(featureLaunchContextProvider.notifier).publish(value);
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
