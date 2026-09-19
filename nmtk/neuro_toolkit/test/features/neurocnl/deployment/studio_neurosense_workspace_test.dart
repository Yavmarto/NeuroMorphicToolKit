import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/neurosense_workspace/neurosense_source_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/neurosense_workspace/studio_neurosense_workspace.dart';
import 'package:neuro_toolkit/features/neurocnl/models/neurosense_sensor_target.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

Future<void> _pumpWorkspace(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: ZetaProvider(
        initialContrast: ZetaContrast.aa,
        initialThemeMode: ThemeMode.light,
        builder: (context, light, dark, mode) => MaterialApp(
          theme: light,
          darkTheme: dark,
          themeMode: mode,
          home: const Scaffold(body: StudioNeuroSenseWorkspace()),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'StudioNeuroSenseWorkspace prompts to configure a source when none is set',
    (tester) async {
      await _pumpWorkspace(tester);

      expect(
        find.byKey(const Key('neurosense-configure-source')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('neurosense-reconfigure-source')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'StudioNeuroSenseWorkspace shows the configured device once set',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            neuroSenseSourceProvider.overrideWith(
              () => _FakeConfiguredNotifier(),
            ),
          ],
          child: ZetaProvider(
            initialContrast: ZetaContrast.aa,
            initialThemeMode: ThemeMode.light,
            builder: (context, light, dark, mode) => MaterialApp(
              theme: light,
              darkTheme: dark,
              themeMode: mode,
              home: const Scaffold(body: StudioNeuroSenseWorkspace()),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Device'), findsOneWidget);
      expect(find.text('fake-sensor'), findsOneWidget);
      expect(
        find.byKey(const Key('neurosense-reconfigure-source')),
        findsOneWidget,
      );
    },
  );
}

class _FakeConfiguredNotifier extends NeuroSenseSourceNotifier {
  @override
  NeuroSenseSensorConfig? build() {
    return const NeuroSenseSensorConfig(
      device: NeurosenseDeviceInfo(
        id: 'dev-1',
        name: 'fake-sensor',
        type: 'synthetic',
        channels: 4,
        samplingRateHz: 250,
        connected: false,
      ),
      channel: 0,
      sampleRateHz: 250,
    );
  }
}
