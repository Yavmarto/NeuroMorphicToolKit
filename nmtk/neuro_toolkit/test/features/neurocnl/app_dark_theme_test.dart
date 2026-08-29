// Regression test for the "white canvas in dark mode" bug.
//
// The root app now owns the only MaterialApp and theme provider. This guards
// the feature test host against regressing the inherited dark canvas tokens.
//
// It also locks in the single-MaterialApp feature integration invariant.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

import 'support/neurocnl_surface_test_host.dart';

void main() {
  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({
      'neurocnl_server_url': 'http://localhost:8000',
    });
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
  });

  testWidgets(
    'neurocnl Studio wires darkTheme and resolves the dark canvas token',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildNeurocnlSurfaceTestHost(themeMode: ThemeMode.dark),
      );
      await tester.pumpAndSettle();

      final MaterialApp app = tester.widget<MaterialApp>(
        find.byType(MaterialApp),
      );
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(
        app.darkTheme,
        isNotNull,
        reason:
            'darkTheme must be wired so dark mode does not fall back '
            'to the light ThemeData.',
      );
      expect(app.themeMode, ThemeMode.dark);

      final BuildContext context = tester.element(find.byType(Navigator).first);
      expect(
        NmtkShellTokens.of(context).canvasBackground,
        const Color(0xFF020617),
        reason:
            'In dark mode the canvas background must resolve to the dark '
            'shell token, not white (0xFFFFFFFF).',
      );

      // Guard the Zeta layer too: canvas nodes fill with
      // Zeta.of(context).colors.surfacePrimary. In dark mode this must be a
      // dark surface so nodes stay legible and the canvas does not whitewash.
      final Color nodeFill = Zeta.of(context).colors.surfacePrimary;
      expect(
        nodeFill.computeLuminance(),
        lessThan(0.5),
        reason:
            'Zeta surfacePrimary (canvas node fill) must resolve dark in '
            'dark mode, not fall back to a light surface.',
      );
    },
  );
}
