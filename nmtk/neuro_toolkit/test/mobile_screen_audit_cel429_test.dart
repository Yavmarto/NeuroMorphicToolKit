// CEL-429 mobile-standard audit for `lib/screens/*`.
//
// Pumps each audited full-page screen / surface at the two required narrow
// widths (375x667 iPhone SE, 390x844 iPhone 14) and fails on a RenderFlex
// overflow. Also:
//   * asserts a visible back/cancel affordance in every step-flow state, and
//   * measures the rendered contrast of the themed controls each surface paints
//     in both dark and light themes (WCAG 1.4.11 >= 3:1), so a passing
//     theme-API audit is not mistaken for legibility.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/features/server/provision/provision_notifier.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/environment_editor.dart';
import 'package:neuro_toolkit/screens/server_access_dialog_surface.dart';
import 'package:neuro_toolkit/screens/server_access_gate.dart';
import 'package:neuro_toolkit/screens/server_access_popup.dart';
import 'package:neuro_toolkit/screens/server_access_sheet_surface.dart';
import 'package:neuro_toolkit/screens/server_connect_screen.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/screens/tool_view/launcher_profile_button.dart';
import 'package:neuro_toolkit/screens/tool_view/server_connection_control.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/environment_api_service.dart';
import 'package:neuro_toolkit/src/features/module/domain/module_state.dart';
import 'package:neuro_toolkit/src/features/module/presentation/module_notifier.dart';
import 'package:neuro_toolkit/src/features/server_connection/presentation/server_connection_notifier.dart';
import 'package:neuro_toolkit/src/features/workspace/domain/workspace_state.dart';
import 'package:neuro_toolkit/src/features/workspace/presentation/workspace_notifier.dart';

const Size _iphoneSe = Size(375, 667);
const Size _iphone14 = Size(390, 844);
const List<Size> _phoneSizes = <Size>[_iphoneSe, _iphone14];

// ── Test doubles ─────────────────────────────────────────────────────────────

class _StubConnectNotifier extends ConnectNotifier {
  _StubConnectNotifier([this._initial]);

  final ConnectState? _initial;

  @override
  ConnectState build() => _initial ?? const ConnectState();

  @override
  Future<void> reconnectOnOpen() async {}

  @override
  Future<void> connect(ConnectRequest request) async {}

  @override
  void continueWithoutServer() {}
}

/// Keeps the gate in its reconnecting state forever so the overlay's cancel
/// affordance can be exercised.
class _HangingConnectNotifier extends ConnectNotifier {
  @override
  ConnectState build() => const ConnectState();

  @override
  Future<void> reconnectOnOpen() {
    state = state.copyWith(phase: ConnectPhase.reconnecting);
    return Completer<void>().future;
  }

  @override
  Future<void> connect(ConnectRequest request) async {}

  @override
  void continueWithoutServer() {}
}

class _StubProvisionNotifier extends ProvisionNotifier {
  @override
  ProvisionState build() => const ProvisionState();

  @override
  Future<void> provision(ProvisionRequest request) async {}
}

class _FakeModuleNotifier extends ModuleNotifier {
  @override
  Future<ModuleState> build() async {
    return ModuleState(
      modules: <Module>[
        Module(
          id: 'neurocnl',
          name: 'NeuroStudio',
          description: 'CNL compiler and visual design suite',
          directory: 'neurocnl',
          hasFrontend: true,
          status: ModuleStatus.starting,
        ),
        Module(
          id: 'Neurobench',
          name: 'Bench',
          description: 'SNN benchmarking workspace',
          directory: 'Neurobench',
          hasFrontend: true,
          status: ModuleStatus.starting,
        ),
      ],
    );
  }
}

class _FakeWorkspaceNotifier extends WorkspaceNotifier {
  @override
  Future<WorkspaceState> build() async {
    return const WorkspaceState(
      sessions: <WorkspaceSession>[
        WorkspaceSession(
          moduleId: 'neurocnl',
          surfaceMode: 'embedded',
          readinessState: 'warming_up',
        ),
        WorkspaceSession(
          moduleId: 'Neurobench',
          surfaceMode: 'embedded',
          readinessState: 'warming_up',
        ),
      ],
      focusedModuleId: 'neurocnl',
    );
  }

  @override
  Future<void> ensureDefaultSessionsOnce({
    required List<WorkspaceSession> sessions,
    required String? focusedModuleId,
  }) async {}

  @override
  Future<void> openSession(
    String moduleId, {
    required String surfaceMode,
    String? deepLink,
    Map<String, dynamic> restoreState = const <String, dynamic>{},
    String readinessState = 'opening',
  }) async {}

  @override
  Future<void> focusSession(String moduleId) async {}

  @override
  Future<void> updateSession(
    String moduleId, {
    String? deepLink,
    Map<String, dynamic>? restoreState,
    String? readinessState,
  }) async {}

  @override
  Future<void> closeSession(String moduleId) async {}
}

class _FakeConnectionNotifier extends ServerConnectionNotifier {
  @override
  ServerConnectionState build() => ServerConnectionState(
    phase: ServerConnectionPhase.connected,
    baseUri: Uri.parse('http://localhost:9000'),
  );
}

class _FakeEnvironmentApi extends EnvironmentApiService {
  _FakeEnvironmentApi({
    this.environments = const <EnvironmentInfo>[],
    this.listGate,
  }) : super(
         controlApi: ControlApiService(
           baseUri: Uri.parse('http://localhost:9000'),
           analyticsService: AnalyticsService(),
         ),
       );

  final List<EnvironmentInfo> environments;
  final Completer<List<EnvironmentInfo>>? listGate;

  @override
  Future<List<EnvironmentInfo>> listEnvironments() {
    final gate = listGate;
    if (gate != null) return gate.future;
    return Future<List<EnvironmentInfo>>.value(environments);
  }

  @override
  Future<List<PackageInfo>> listPackages(String slug) async {
    return const <PackageInfo>[
      PackageInfo(name: 'numpy', version: '1.26.0'),
      PackageInfo(
        name: 'a-very-long-package-name-that-wraps',
        version: '9.9.9',
      ),
    ];
  }

  @override
  Future<String> exportRequirements(
    String slug, {
    String mode = 'delta',
  }) async {
    return 'numpy==1.26.0\ncowsay==6.1\n';
  }
}

List<EnvironmentInfo> _environments() => const <EnvironmentInfo>[
  EnvironmentInfo(
    slug: 'base',
    displayName: 'Python (NeuroStudio)',
    kernelName: 'python3',
    immutable: true,
    pythonVersion: '3.11',
    packageCount: 142,
  ),
  EnvironmentInfo(
    slug: 'shared',
    displayName: 'Shared experiment with a deliberately long name',
    kernelName: 'shared',
    immutable: false,
    pythonVersion: '3.11',
    packageCount: 4,
  ),
];

// ── Harness helpers ──────────────────────────────────────────────────────────

/// Mirrors the proven CEL-421/CEL-430 harness: `ZetaProvider` direct (not
/// `NmtkZetaTheme.wrap`, whose async custom-theme load never settles in tests).
Widget _app({
  required Widget home,
  List<Override> overrides = const <Override>[],
  ThemeMode mode = ThemeMode.dark,
}) {
  return ZetaProvider(
    initialContrast: ZetaContrast.aa,
    initialThemeMode: mode,
    builder: (context, light, dark, effective) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        themeMode: effective,
        home: home,
      ),
    ),
  );
}

void _useViewport(WidgetTester tester, Size size, {double keyboard = 0}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
}

/// Bounded settle: several screens keep an indeterminate spinner or a blinking
/// text caret alive, so `pumpAndSettle` would time out.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<List<String>> _captureOverflows(Future<void> Function() body) async {
  final overflows = <String>[];
  final original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final message = details.exceptionAsString();
    if (message.contains('overflowed by')) {
      overflows.add(message);
      return;
    }
    original?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
  return overflows;
}

void _expectNoOverflow(List<String> overflows, String label) {
  expect(overflows, isEmpty, reason: '$label: ${overflows.join('\n')}');
}

List<Override> _toolViewOverrides() => <Override>[
  analyticsServiceProvider.overrideWithValue(AnalyticsService()),
  selectedControlApiServiceProvider.overrideWithValue(
    ControlApiService(
      baseUri: Uri.parse('http://localhost:9000'),
      analyticsService: AnalyticsService(),
    ),
  ),
  moduleProvider.overrideWith(_FakeModuleNotifier.new),
  workspaceProvider.overrideWith(_FakeWorkspaceNotifier.new),
];

List<Override> _connectionOverrides() => <Override>[
  selectedControlApiServiceProvider.overrideWithValue(
    ControlApiService(
      baseUri: Uri.parse('http://localhost:9000'),
      analyticsService: AnalyticsService(),
    ),
  ),
  moduleProvider.overrideWith(_FakeModuleNotifier.new),
  serverConnectionProvider.overrideWith(_FakeConnectionNotifier.new),
  backendVersionProvider.overrideWith((ref) async => '1.0.0'),
];

// ── Contrast helpers (WCAG relative luminance) ───────────────────────────────

Color _over(Color fg, Color bg) {
  if (fg.a >= 0.999) return fg;
  return Color.from(
    alpha: 1.0,
    red: fg.r * fg.a + bg.r * (1 - fg.a),
    green: fg.g * fg.a + bg.g * (1 - fg.a),
    blue: fg.b * fg.a + bg.b * (1 - fg.a),
  );
}

double _channelLuminance(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channelLuminance(c.r) +
    0.7152 * _channelLuminance(c.g) +
    0.0722 * _channelLuminance(c.b);

double _contrastRatio(Color fg, Color bg) {
  final blended = _over(fg, bg);
  final la = _luminance(blended);
  final lb = _luminance(bg);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

String _hex(Color c) =>
    '#${(c.r * 255).round().toRadixString(16).padLeft(2, '0')}'
    '${(c.g * 255).round().toRadixString(16).padLeft(2, '0')}'
    '${(c.b * 255).round().toRadixString(16).padLeft(2, '0')}';

Color? _nearestOpaqueBackground(Element element) {
  Color? found;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Container) {
      final decoration = widget.decoration;
      if (decoration is BoxDecoration) {
        final color = decoration.color;
        if (color != null && color.a >= 0.999) {
          found = color;
          return false;
        }
      }
      final color = widget.color;
      if (color != null && color.a >= 0.999) {
        found = color;
        return false;
      }
    } else if (widget is Material) {
      final color = widget.color;
      if (color != null && color.a >= 0.999) {
        found = color;
        return false;
      }
    } else if (widget is ColoredBox) {
      final color = widget.color;
      if (color.a >= 0.999) {
        found = color;
        return false;
      }
    }
    return true;
  });
  return found;
}

/// Measures every visible icon's rendered ink against its nearest opaque
/// ancestor background and asserts the WCAG 1.4.11 3:1 non-text floor.
void _expectIconContrast(
  WidgetTester tester,
  String label, {
  double minimum = 3.0,
}) {
  final icons = find.byType(Icon);
  expect(icons, findsWidgets, reason: '$label: expected at least one icon');
  var checked = 0;
  for (final element in icons.evaluate()) {
    final icon = element.widget as Icon;
    final color = icon.color ?? IconTheme.of(element).color;
    if (color == null) continue;
    final background = _nearestOpaqueBackground(element);
    if (background == null) continue;
    final ratio = _contrastRatio(color, background);
    debugPrint(
      'contrast $label ${icon.icon}: ${_hex(color)} vs ${_hex(background)} '
      '= ${ratio.toStringAsFixed(2)}',
    );
    expect(
      ratio,
      greaterThanOrEqualTo(minimum),
      reason:
          '$label: ${icon.icon} rendered ${ratio.toStringAsFixed(2)}:1 '
          '(${_hex(color)} on ${_hex(background)}), below the '
          '${minimum.toStringAsFixed(1)}:1 floor',
    );
    checked++;
  }
  expect(checked, greaterThan(0), reason: '$label: no icon contrast measured');
}

void main() {
  group('overflow @ 375x667 and 390x844', () {
    testWidgets('tool_view.dart mounts the mobile scaffold without overflow', (
      tester,
    ) async {
      for (final size in _phoneSizes) {
        _useViewport(tester, size);
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(
            _app(home: const ToolViewScreen(), overrides: _toolViewOverrides()),
          );
          await _settle(tester);
        });
        _expectNoOverflow(overflows, 'tool_view.dart ${size.width.toInt()}');
      }
    });

    testWidgets('server_connect_screen.dart standalone form fits', (
      tester,
    ) async {
      for (final size in _phoneSizes) {
        _useViewport(tester, size);
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(
            _app(
              home: const ServerConnectScreen(showDevBypass: true),
              overrides: <Override>[
                connectNotifierProvider.overrideWith(_StubConnectNotifier.new),
              ],
            ),
          );
          await _settle(tester);
        });
        expect(find.byKey(const Key('server-connect-host')), findsOneWidget);
        _expectNoOverflow(
          overflows,
          'server_connect_screen.dart ${size.width.toInt()}',
        );
      }
    });

    testWidgets('server_connect_screen.dart embedded in the popup fits', (
      tester,
    ) async {
      for (final size in _phoneSizes) {
        _useViewport(tester, size);
        final overrides = <Override>[
          connectNotifierProvider.overrideWith(_StubConnectNotifier.new),
          provisionNotifierProvider.overrideWith(_StubProvisionNotifier.new),
        ];
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(
            _app(
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ZetaButton(
                      label: 'Open',
                      onPressed: () => showServerAccessPopup(context),
                    ),
                  ),
                ),
              ),
              overrides: overrides,
            ),
          );
          await _settle(tester);
          await tester.tap(find.text('Open'));
          await _settle(tester);
        });
        _expectNoOverflow(
          overflows,
          'server_access_popup.dart ${size.width.toInt()}',
        );
        expect(find.byType(ServerAccessSheetSurface), findsOneWidget);
      }
    });

    testWidgets('server_access_dialog_surface.dart caps to the viewport', (
      tester,
    ) async {
      for (final size in <Size>[_iphoneSe, _iphone14, const Size(1024, 600)]) {
        _useViewport(tester, size);
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(
            _app(
              home: Scaffold(
                body: ServerAccessDialogSurface(child: _longFormBody()),
              ),
            ),
          );
          await _settle(tester);
        });
        expect(find.text('Field 0'), findsOneWidget);
        _expectNoOverflow(
          overflows,
          'server_access_dialog_surface.dart ${size.width.toInt()}',
        );
      }
    });

    testWidgets('server_access_sheet_surface.dart clears the keyboard', (
      tester,
    ) async {
      const keyboard = 300.0;
      _useViewport(tester, _iphone14, keyboard: keyboard);
      final overflows = await _captureOverflows(() async {
        await tester.pumpWidget(
          _app(
            home: Scaffold(
              body: ServerAccessSheetSurface(child: _longFormBody()),
            ),
          ),
        );
        await _settle(tester);
      });
      _expectNoOverflow(overflows, 'server_access_sheet_surface.dart keyboard');
      final sheetBox = tester.getRect(
        find.descendant(
          of: find.byType(ServerAccessSheetSurface),
          matching: find.byType(ClipRRect),
        ),
      );
      expect(
        sheetBox.bottom,
        lessThanOrEqualTo(_iphone14.height - keyboard + 0.5),
        reason: 'sheet content must sit above the keyboard',
      );
    });

    testWidgets('server_access_gate.dart popup fits on a phone', (
      tester,
    ) async {
      for (final size in _phoneSizes) {
        _useViewport(tester, size);
        final overrides = <Override>[
          connectNotifierProvider.overrideWith(_StubConnectNotifier.new),
          provisionNotifierProvider.overrideWith(_StubProvisionNotifier.new),
        ];
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(
            _app(
              home: const ServerAccessGate(
                child: Scaffold(body: Center(child: Text('WORKSPACE'))),
              ),
              overrides: overrides,
            ),
          );
          await _settle(tester);
        });
        expect(find.byKey(const Key('server-connect-host')), findsOneWidget);
        _expectNoOverflow(
          overflows,
          'server_access_gate.dart ${size.width.toInt()}',
        );
      }
    });

    testWidgets('environment_editor.dart fits with a long environment list', (
      tester,
    ) async {
      for (final size in _phoneSizes) {
        _useViewport(tester, size);
        final overrides = <Override>[
          environmentApiServiceProvider.overrideWithValue(
            _FakeEnvironmentApi(environments: _environments()),
          ),
        ];
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(
            _app(home: const EnvironmentEditorScreen(), overrides: overrides),
          );
          await _settle(tester);
        });
        expect(find.text('Python Environments'), findsOneWidget);
        expect(find.text('Python (NeuroStudio)'), findsWidgets);
        _expectNoOverflow(
          overflows,
          'environment_editor.dart ${size.width.toInt()}',
        );
      }
    });

    testWidgets('environment_editor export dialog fits on a phone', (
      tester,
    ) async {
      _useViewport(tester, _iphoneSe);
      final overrides = <Override>[
        environmentApiServiceProvider.overrideWithValue(
          _FakeEnvironmentApi(environments: _environments()),
        ),
      ];
      final overflows = await _captureOverflows(() async {
        await tester.pumpWidget(
          _app(home: const EnvironmentEditorScreen(), overrides: overrides),
        );
        await _settle(tester);
        await tester.scrollUntilVisible(find.text('Export…').first, 200);
        await _settle(tester);
        await tester.tap(find.text('Export…').first);
        await _settle(tester);
      });
      expect(find.textContaining('Export "'), findsOneWidget);
      _expectNoOverflow(overflows, 'environment_editor export dialog');
    });

    testWidgets('environment_editor import dialog fits on a phone', (
      tester,
    ) async {
      _useViewport(tester, _iphoneSe);
      final overrides = <Override>[
        environmentApiServiceProvider.overrideWithValue(
          _FakeEnvironmentApi(environments: _environments()),
        ),
      ];
      final overflows = await _captureOverflows(() async {
        await tester.pumpWidget(
          _app(home: const EnvironmentEditorScreen(), overrides: overrides),
        );
        await _settle(tester);
        await tester.ensureVisible(find.text('Import requirements…'));
        await tester.tap(find.text('Import requirements…'));
        await _settle(tester);
      });
      expect(find.text('Import requirements'), findsOneWidget);
      _expectNoOverflow(overflows, 'environment_editor import dialog');
    });

    testWidgets('server_connection_control icon-only badge fits', (
      tester,
    ) async {
      for (final size in _phoneSizes) {
        _useViewport(tester, size);
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(
            _app(
              home: const Scaffold(
                body: Center(
                  child: InlineServerConnectionControl(
                    onPressed: _noop,
                    iconOnly: true,
                  ),
                ),
              ),
              overrides: _connectionOverrides(),
            ),
          );
          await _settle(tester);
        });
        expect(find.byType(NmtkStatusBadge), findsOneWidget);
        _expectNoOverflow(
          overflows,
          'server_connection_control.dart ${size.width.toInt()}',
        );
      }
    });

    testWidgets('launcher_profile_button fits and stays tappable', (
      tester,
    ) async {
      for (final size in _phoneSizes) {
        _useViewport(tester, size);
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(
            _app(
              home: const Scaffold(
                body: Center(child: LauncherProfileButton()),
              ),
            ),
          );
          await _settle(tester);
        });
        _expectNoOverflow(
          overflows,
          'launcher_profile_button.dart ${size.width.toInt()}',
        );
        expect(find.byTooltip('Profile'), findsOneWidget);
      }
    });
  });

  group('back / cancel affordance in every step-flow state', () {
    testWidgets('connect flow keeps a Close affordance in initial + setup', (
      tester,
    ) async {
      _useViewport(tester, _iphoneSe);
      final overrides = <Override>[
        connectNotifierProvider.overrideWith(_StubConnectNotifier.new),
        provisionNotifierProvider.overrideWith(_StubProvisionNotifier.new),
      ];
      await tester.pumpWidget(
        _app(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ZetaButton(
                  label: 'Open',
                  onPressed: () => showServerAccessPopup(context),
                ),
              ),
            ),
          ),
          overrides: overrides,
        ),
      );
      await _settle(tester);
      await tester.tap(find.text('Open'));
      await _settle(tester);

      // Initial (connect) state.
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.bySemanticsLabel('Close'), findsOneWidget);

      // Setup state: an explicit Back returns to the connect form.
      await tester.ensureVisible(
        find.byKey(const Key('server-connect-new-server')),
      );
      await tester.tap(find.byKey(const Key('server-connect-new-server')));
      await _settle(tester);
      expect(find.byKey(const Key('server-setup-back')), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);

      await tester.tap(find.byKey(const Key('server-setup-back')));
      await _settle(tester);
      expect(
        find.byKey(const Key('server-connect-new-server')),
        findsOneWidget,
      );
    });

    testWidgets(
      'reconnecting overlay offers a cancel path (no OS back needed)',
      (tester) async {
        _useViewport(tester, _iphoneSe);
        final overrides = <Override>[
          connectNotifierProvider.overrideWith(_HangingConnectNotifier.new),
          provisionNotifierProvider.overrideWith(_StubProvisionNotifier.new),
        ];
        await tester.pumpWidget(
          _app(
            home: const ServerAccessGate(
              child: Scaffold(body: Center(child: Text('WORKSPACE'))),
            ),
            overrides: overrides,
          ),
        );
        await _settle(tester);

        expect(find.text('Reconnecting to your server…'), findsOneWidget);
        final cancel = find.byKey(const Key('server-access-reconnect-cancel'));
        expect(
          cancel,
          findsOneWidget,
          reason: 'reconnect overlay needs a cancel affordance',
        );

        await tester.tap(cancel);
        await _settle(tester);
        // The sign-in popup is now reachable without an OS back gesture.
        expect(find.byTooltip('Close'), findsOneWidget);
      },
    );

    testWidgets('environment editor keeps app-bar chrome while loading', (
      tester,
    ) async {
      _useViewport(tester, _iphoneSe);
      final gate = Completer<List<EnvironmentInfo>>();
      final overrides = <Override>[
        environmentApiServiceProvider.overrideWithValue(
          _FakeEnvironmentApi(listGate: gate),
        ),
      ];
      await tester.pumpWidget(
        _app(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ZetaButton(
                  label: 'Open',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const EnvironmentEditorScreen(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          overrides: overrides,
        ),
      );
      await _settle(tester);
      await tester.tap(find.text('Open'));
      await _settle(tester);

      // Still loading, but the back affordance exists in this state.
      expect(find.text('Python Environments'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);

      gate.complete(_environments());
      await _settle(tester);
      expect(find.text('Python Environments'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.text('Python (NeuroStudio)'), findsWidgets);
    });
  });

  group('rendered contrast (light + dark)', () {
    for (final mode in <ThemeMode>[ThemeMode.dark, ThemeMode.light]) {
      testWidgets('launcher_profile_button icon clears 3:1 (${mode.name})', (
        tester,
      ) async {
        _useViewport(tester, _iphone14);
        await tester.pumpWidget(
          _app(
            home: const Scaffold(body: Center(child: LauncherProfileButton())),
            mode: mode,
          ),
        );
        await _settle(tester);
        _expectIconContrast(tester, 'launcher_profile_button/${mode.name}');
      });

      testWidgets('server_connection_control icon clears 3:1 (${mode.name})', (
        tester,
      ) async {
        _useViewport(tester, _iphone14);
        await tester.pumpWidget(
          _app(
            home: const Scaffold(
              body: Center(
                child: InlineServerConnectionControl(
                  onPressed: _noop,
                  iconOnly: true,
                ),
              ),
            ),
            overrides: _connectionOverrides(),
            mode: mode,
          ),
        );
        await _settle(tester);
        _expectIconContrast(tester, 'server_connection_control/${mode.name}');
      });
    }
  });
}

void _noop() {}

Widget _longFormBody() {
  return Column(
    children: <Widget>[
      const Row(
        children: <Widget>[
          ZetaButton.text(label: 'Back', onPressed: _noop),
          Spacer(),
          ZetaIconButton.text(
            icon: ZetaIcons.close,
            semanticLabel: 'Close',
            onPressed: _noop,
          ),
        ],
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: <Widget>[
              for (var i = 0; i < 30; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ZetaTextInput(label: 'Field $i'),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}
