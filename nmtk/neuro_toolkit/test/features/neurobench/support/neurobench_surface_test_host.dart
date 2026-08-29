import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurobench/app.dart';
import 'package:neuro_toolkit/features/neurobench/providers/feature_launch_provider.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

const String kTestNeurobenchServerUrl = 'http://127.0.0.1:9000/api/neurobench';

Future<void> noopEditServer() async {}

Widget buildNeurobenchSurfaceTestHost({
  String initialLocation = '/',
  String initialServerUrl = kTestNeurobenchServerUrl,
  ThemeMode themeMode = ThemeMode.dark,
}) {
  return ProviderScope(
    overrides: [
      initialLocationProvider.overrideWithValue(initialLocation),
      showShellChromeProvider.overrideWithValue(true),
      featureLaunchContextProvider.overrideWithValue(
        NmtkFeatureLaunchContext(
          moduleId: NmtkModuleId.neurobench,
          backendUri: Uri.parse(initialServerUrl),
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
        home: const NeuroBenchWorkbenchSurface(),
      ),
    ),
  );
}
