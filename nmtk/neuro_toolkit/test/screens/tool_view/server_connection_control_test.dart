import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/tool_view/server_connection_control.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/src/features/module/domain/module_state.dart';
import 'package:neuro_toolkit/src/features/module/presentation/module_notifier.dart';
import 'package:neuro_toolkit/src/features/server_connection/presentation/server_connection_notifier.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

Module _module(ModuleStatus status, {bool required = false}) => Module(
  id: 'module-id',
  name: 'Module',
  description: 'A test module',
  directory: 'module',
  required: required,
  status: status,
);

class _FakeModuleNotifier extends ModuleNotifier {
  _FakeModuleNotifier(this._modules);

  final List<Module> _modules;

  @override
  Future<ModuleState> build() async => ModuleState(modules: _modules);
}

class _FakeConnectionNotifier extends ServerConnectionNotifier {
  _FakeConnectionNotifier(this._state);

  final ServerConnectionState _state;

  @override
  ServerConnectionState build() => _state;
}

class _FakeBackendDegradedNotifier extends NeurocnlBackendDegradedNotifier {
  _FakeBackendDegradedNotifier(this._value);

  final bool _value;

  @override
  bool build() => _value;
}

Widget _harness(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void _noop() {}

ControlApiService _controlApi() => ControlApiService(
  baseUri: Uri.parse('http://localhost:9000'),
  analyticsService: AnalyticsService(),
);

ServerConnectionState _connected() => ServerConnectionState(
  phase: ServerConnectionPhase.connected,
  baseUri: Uri.parse('http://localhost:9000'),
);

Future<void> _pump({
  required WidgetTester tester,
  required List<Module> modules,
  ServerConnectionState connection = const ServerConnectionState.disconnected(),
  bool backendDegraded = false,
  bool hasControlApi = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        selectedControlApiServiceProvider.overrideWithValue(
          hasControlApi ? _controlApi() : null,
        ),
        moduleProvider.overrideWith(() => _FakeModuleNotifier(modules)),
        serverConnectionProvider.overrideWith(
          () => _FakeConnectionNotifier(connection),
        ),
        neurocnlBackendDegradedProvider.overrideWith(
          () => _FakeBackendDegradedNotifier(backendDegraded),
        ),
        backendVersionProvider.overrideWith((ref) async => '1.0.0'),
      ],
      child: _harness(
        const InlineServerConnectionControl(onPressed: _noop, iconOnly: true),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

Color _badgeForeground(WidgetTester tester, NmtkTone tone) {
  final context = tester.element(find.byType(NmtkStatusBadge));
  return resolveNmtkTonePalette(context, tone).foreground;
}

void main() {
  testWidgets(
    'degraded module turns the connection dot orange',
    (tester) async {
      await _pump(
        tester: tester,
        modules: [_module(ModuleStatus.degraded)],
        connection: _connected(),
      );

      expect(find.byTooltip('Server connection · A module is degraded'), findsOneWidget);
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byType(NmtkStatusBadge),
          matching: find.byIcon(ZetaIcons.radio_button_checked),
        ),
      );
      expect(
        icon.color,
        _badgeForeground(tester, NmtkTone.warning),
      );
    },
  );

  testWidgets('no degraded module keeps the connected dot green', (
    tester,
  ) async {
    await _pump(
      tester: tester,
      modules: [_module(ModuleStatus.running)],
      connection: _connected(),
    );

    expect(find.byTooltip('Server connection · Connected'), findsOneWidget);
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byType(NmtkStatusBadge),
        matching: find.byIcon(ZetaIcons.radio_button_checked),
      ),
    );
    expect(
      icon.color,
      _badgeForeground(tester, NmtkTone.success),
    );
  });

  testWidgets('backend degraded takes precedence over healthy modules', (
    tester,
  ) async {
    await _pump(
      tester: tester,
      modules: [_module(ModuleStatus.running)],
      connection: _connected(),
      backendDegraded: true,
    );

    expect(
      find.byTooltip('Server connection · Module backend degraded'),
      findsOneWidget,
    );
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byType(NmtkStatusBadge),
        matching: find.byIcon(ZetaIcons.radio_button_checked),
      ),
    );
    expect(icon.color, _badgeForeground(tester, NmtkTone.warning));
  });

  testWidgets('launcher ping red (disconnected) wins over a degraded module', (
    tester,
  ) async {
    await _pump(
      tester: tester,
      modules: [_module(ModuleStatus.degraded)],
      connection: const ServerConnectionState.disconnected(),
      hasControlApi: false,
    );

    expect(find.byTooltip('Server connection · A module is degraded'), findsOneWidget);
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byType(NmtkStatusBadge),
        matching: find.byIcon(ZetaIcons.radio_button_checked),
      ),
    );
    expect(icon.color, _badgeForeground(tester, NmtkTone.danger));
  });
}
