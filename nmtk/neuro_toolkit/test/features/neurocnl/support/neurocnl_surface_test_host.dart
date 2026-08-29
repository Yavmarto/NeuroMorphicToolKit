import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/app.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/feature_launch_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

const String kTestNeurocnlServerUrl = 'http://127.0.0.1:9000/api/neurocnl';

Future<void> noopEditServer() async {}

Widget buildNeurocnlSurfaceTestHost({
  String initialLocation = '/',
  String initialServerUrl = kTestNeurocnlServerUrl,
  String initialAdminToken = '',
  ThemeMode themeMode = ThemeMode.dark,
}) {
  return ProviderScope(
    overrides: [
      featureLaunchContextProvider.overrideWithValue(
        NmtkFeatureLaunchContext(
          moduleId: NmtkModuleId.neurocnl,
          backendUri: Uri.parse(initialServerUrl),
          authentication: NmtkFeatureAuthentication(
            adminToken: initialAdminToken,
          ),
          onNavigate: (_) async => false,
          onReportError: (_) async {},
          onEditServer: noopEditServer,
        ),
      ),
    ],
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
  );
}
