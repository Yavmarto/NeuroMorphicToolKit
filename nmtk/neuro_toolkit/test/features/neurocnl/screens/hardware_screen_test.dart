import 'package:riverpod_annotation/riverpod_annotation.dart';
// ignore_for_file: unused_local_variable
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:mockito/mockito.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' show ZetaButton;
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/sensor_frame.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/hardware_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hardware_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../providers_test.mocks.dart';

// ── Helpers ────────────────────────────────────────────────────────────────

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

HardwareState _stateWith({
  bool isConnected = false,
  String? connectedPort,
  List<String> availablePorts = const [],
  List<SensorFrame> sensorData = const [],
  bool isRefreshing = false,
  String? errorMessage,
}) {
  return HardwareState(
    isConnected: isConnected,
    connectedPort: connectedPort,
    availablePorts: availablePorts,
    sensorData: sensorData,
    isRefreshing: isRefreshing,
    errorMessage: errorMessage,
  );
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  late MockApiClient mockApi;

  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
    mockApi = MockApiClient();
    // listSerialPorts is called on initState via refreshPorts.
    when(mockApi.listSerialPorts()).thenAnswer((_) async => <String>[]);
  });

  // ── 1. Connect button disabled when no port selected ───────────────────

  testWidgets('Connect button is disabled when selectedPort is null', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        const HardwareScreen(),
        overrides: [apiClientProvider.overrideWithValue(mockApi)],
      ),
    );
    await tester.pumpAndSettle();

    // With no port selected the Connect ZetaButton must be disabled.
    final connectFinder = find.widgetWithText(ZetaButton, 'Connect');
    expect(connectFinder, findsOneWidget);

    final button = tester.widget<ZetaButton>(connectFinder);
    expect(
      button.onPressed,
      isNull,
      reason: 'Connect must be disabled when no port is selected',
    );
  });

  // ── 2. Error text is shown when state.errorMessage is not null ─────────

  testWidgets(
    'Error message text is visible when hardware state has an error',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const errorMessage = 'Connection failed: port busy';

      await tester.pumpWidget(
        _wrap(
          const HardwareScreen(),
          overrides: [
            apiClientProvider.overrideWithValue(mockApi),
            hardwareProvider.overrideWith(
              () => _FakeHardwareController(
                _stateWith(errorMessage: errorMessage),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(errorMessage), findsOneWidget);
    },
  );

  // ── 3. Telemetry panel shows waiting message when connected + empty ─────

  testWidgets(
    'Telemetry panel shows waiting message when connected but sensorData is empty',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          const HardwareScreen(),
          overrides: [
            apiClientProvider.overrideWithValue(mockApi),
            hardwareProvider.overrideWith(
              () => _FakeHardwareController(
                _stateWith(
                  isConnected: true,
                  connectedPort: '/dev/ttyUSB0',
                  sensorData: const [],
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Waiting for telemetry preview data…'), findsOneWidget);
    },
  );

  // ── 4. Telemetry panel shows disconnected placeholder when not connected

  testWidgets(
    'Telemetry panel shows disconnected placeholder when not connected',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          const HardwareScreen(),
          overrides: [apiClientProvider.overrideWithValue(mockApi)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Connect to a device'), findsOneWidget);
    },
  );

  // ── 5. Handoff panel buttons are always present ────────────────────────

  testWidgets(
    'Handoff panel shows NeuroSense and Neurochip navigation buttons',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          const HardwareScreen(),
          overrides: [apiClientProvider.overrideWithValue(mockApi)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Open NeuroSense Monitor'), findsOneWidget);
      expect(find.textContaining('in Neurochip'), findsOneWidget);
    },
  );
}

// ── Fakes ──────────────────────────────────────────────────────────────────

/// A no-op notifier that starts with a pre-built [HardwareState] and never
/// makes network calls — used to inject specific states in tests.
class _FakeHardwareController extends HardwareController {
  _FakeHardwareController(this._initial);

  final HardwareState _initial;

  @override
  HardwareState build() => _initial;

  @override
  Future<void> refreshPorts() async {
    // no-op — no API calls in unit tests
  }
}
