import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/neurosense_sensor_target.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/neurosense_popup.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurosense_api_service.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class _FakeNeurosenseApiService extends NeurosenseApiService {
  _FakeNeurosenseApiService() : super(ApiClient(baseUrl: 'http://test'));

  final devices = <NeurosenseDeviceInfo>[
    const NeurosenseDeviceInfo(
      id: 'syn-1',
      name: 'Synthetic board',
      type: 'synthetic',
      channels: 8,
      samplingRateHz: 250,
      connected: false,
    ),
  ];

  final presets = <NeurosenseAcquisitionPreset>[
    const NeurosenseAcquisitionPreset(
      id: 'emg',
      name: 'EMG prosthetic',
      signalType: 'emg',
      description: 'Forearm EMG for prosthetic control.',
    ),
  ];

  final quality = NeurosenseSignalQuality(
    channels: [
      NeurosenseChannelQuality(
        channel: 0,
        label: 'flexor',
        snrDb: 18.5,
        status: 'good',
        suggestion: 'Signal looks clean.',
      ),
    ],
  );

  final encoding = const NeurosenseEncodingConfig(
    method: 'rate',
    rateMaxHz: 200,
  );

  @override
  Future<List<NeurosenseDeviceInfo>> listDevices() async => devices;

  @override
  Future<List<NeurosenseAcquisitionPreset>> listPresets() async => presets;

  @override
  Future<NeurosenseSignalQuality> getQuality() async => quality;

  @override
  Future<NeurosenseEncodingConfig> importNir({
    required String filename,
    required Uint8List bytes,
  }) async => encoding;

  @override
  Future<void> connectDevice(
    String deviceId, {
    String? serialPort,
    bool allowExperimental = false,
  }) async {}
}

Future<void> _pumpPopup(
  WidgetTester tester, {
  NeurosensePopupTab initialTab = NeurosensePopupTab.devices,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        neurosenseApiServiceProvider.overrideWithValue(
          _FakeNeurosenseApiService(),
        ),
      ],
      child: ZetaProvider(
        initialContrast: ZetaContrast.aa,
        initialThemeMode: ThemeMode.light,
        builder: (context, light, dark, mode) => MaterialApp(
          theme: light,
          darkTheme: dark,
          themeMode: mode,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () =>
                      showNeurosensePopup(context, initialTab: initialTab),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('showNeurosensePopup opens the modal shell', (tester) async {
    await _pumpPopup(tester);

    expect(find.byType(NeurosensePopup), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Presets'), findsOneWidget);
    expect(find.text('Quality'), findsOneWidget);
    expect(find.text('NIR'), findsOneWidget);
  });

  testWidgets('devices tab lists backend devices', (tester) async {
    await _pumpPopup(tester);

    expect(find.text('Synthetic board'), findsOneWidget);
    expect(find.byKey(const Key('neurosense-popup-scan')), findsOneWidget);
  });

  testWidgets('presets tab lists encoding presets', (tester) async {
    await _pumpPopup(tester, initialTab: NeurosensePopupTab.presets);

    expect(find.text('EMG prosthetic'), findsOneWidget);
  });

  testWidgets('quality tab shows channel metrics', (tester) async {
    await _pumpPopup(tester, initialTab: NeurosensePopupTab.quality);

    expect(find.textContaining('flexor'), findsOneWidget);
    expect(find.textContaining('GOOD'), findsOneWidget);
  });

  testWidgets('golden path: utility pill opens NeuroSense panel', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          neurosenseApiServiceProvider.overrideWithValue(
            _FakeNeurosenseApiService(),
          ),
        ],
        child: ZetaProvider(
          initialContrast: ZetaContrast.aa,
          initialThemeMode: ThemeMode.light,
          builder: (context, light, dark, mode) => MaterialApp(
            theme: light,
            darkTheme: dark,
            themeMode: mode,
            home: Scaffold(body: StudioUtilityPillHarness(onOpen: () {})),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open NeuroSense'));
    await tester.pumpAndSettle();

    expect(find.byType(NeurosensePopup), findsOneWidget);
  });
}

/// Minimal harness that mirrors the utility pill NeuroSense entry.
class StudioUtilityPillHarness extends StatelessWidget {
  const StudioUtilityPillHarness({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Open NeuroSense',
      child: IconButton(
        onPressed: () => showNeurosensePopup(context),
        icon: const Icon(Icons.sensors_outlined),
      ),
    );
  }
}
