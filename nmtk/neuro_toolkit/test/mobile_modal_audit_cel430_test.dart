// CEL-430 mobile audit — neurocnl/screens/* overflow + contrast gates.
//
// Pumps each audited screen at 375×667 (iPhone SE class) and 390×844 (iPhone 14)
// and fails on RenderFlex overflow. Contrast checks measure rendered icon/text
// colors in both light and dark themes (WCAG 1.4.11 ≥ 3:1).
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mockito/mockito.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/hub_preview.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/analysis_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart'
    as pipeline_api;
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/hardware_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/neurohub_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/analysis_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/canvas/export_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/canvas/sweep_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hardware_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/hub_profile_section.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/hub_tag_filter_chip.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/neurohub_sign_in_dialog.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/share_workspace_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/workspace_repo_card.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/workspace_repos_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_session_storage.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/neurocnl/providers_test.mocks.dart';

const Size _iphoneSe = Size(375, 667);
const Size _iphone14 = Size(390, 844);
const List<Size> _phoneSizes = <Size>[_iphoneSe, _iphone14];

final _testGraph = CanvasGraph(
  nodes: <CanvasNode>[
    CanvasNode(
      id: 'n1',
      componentId: 'lif',
      parameters: const <String, dynamic>{'threshold': 1.0},
      position: const <double>[0, 0],
    ),
  ],
  edges: const <CanvasEdge>[],
  metadata: const <String, dynamic>{'zoom': 1.0, 'pan': <double>[0.0, 0.0]},
);

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

void _useViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _zetaApp({
  required Widget home,
  List<Override> overrides = const [],
}) {
  return ZetaProvider(
    initialContrast: ZetaContrast.aa,
    initialThemeMode: ThemeMode.light,
    builder: (context, light, dark, mode) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: light,
        darkTheme: dark,
        themeMode: mode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
}

Future<void> _expectNoOverflowAtPhoneWidths(
  WidgetTester tester,
  String label,
  Widget home, {
  List<Override> overrides = const [],
  Duration? settleDuration,
}) async {
  for (final size in _phoneSizes) {
    _useViewport(tester, size);
    final overflows = await _captureOverflows(() async {
      await tester.pumpWidget(_zetaApp(home: home, overrides: overrides));
      if (settleDuration != null) {
        await tester.pump();
        await tester.pump(settleDuration);
      } else {
        await tester.pumpAndSettle();
      }
    });
    expect(
      overflows,
      isEmpty,
      reason: '$label overflow at ${size.width.toInt()}x${size.height.toInt()}',
    );
  }
}

class _MemoryTokenStorage implements NeurohubTokenStorage {
  _MemoryTokenStorage([this.token]);
  String? token;

  @override
  Future<void> delete() async => token = null;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async => this.token = token;
}

class _StubAnalysisController extends AnalysisController {
  @override
  AnalysisState build() => const AnalysisState();
}

class _StubSpecTextController extends SpecTextController {
  @override
  String build() => 'network n1 { }';
}

double _channelLuminance(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channelLuminance(c.r) +
    0.7152 * _channelLuminance(c.g) +
    0.0722 * _channelLuminance(c.b);

double _contrastRatio(Color fg, Color bg) {
  final la = _luminance(fg);
  final lb = _luminance(bg);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

Color _surfaceColor(WidgetTester tester) {
  final material = tester.widget<Material>(find.byType(Material).first);
  return material.color ?? Colors.white;
}

void main() {
  late MockApiClient mockApi;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
    mockApi = MockApiClient();
    when(mockApi.listSerialPorts()).thenAnswer((_) async => <String>[]);
  });

  group('CEL-430 overflow @ 375×667 and 390×844', () {
    testWidgets('ExportScreen stacks panels on narrow widths', (tester) async {
      await _expectNoOverflowAtPhoneWidths(
        tester,
        'ExportScreen',
        const Scaffold(body: ExportScreen()),
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(
              baseUrl: 'http://test',
              httpClient: MockClient(
                (_) async => throw StateError('unexpected'),
              ),
            ),
          ),
        ],
      );
    });

    testWidgets('SweepScreen stacks panels on narrow widths', (tester) async {
      await _expectNoOverflowAtPhoneWidths(
        tester,
        'SweepScreen',
        const Scaffold(body: SweepScreen()),
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(
              baseUrl: 'http://test',
              httpClient: MockClient(
                (_) async => throw StateError('unexpected'),
              ),
            ),
          ),
        ],
      );
    });

    testWidgets('HardwareScreen scrolls on narrow widths', (tester) async {
      await _expectNoOverflowAtPhoneWidths(
        tester,
        'HardwareScreen',
        const Scaffold(body: HardwareScreen()),
        overrides: [
          pipeline_api.apiClientProvider.overrideWithValue(mockApi),
        ],
      );
    });

    testWidgets('AnalysisScreen tabs fit on narrow widths', (tester) async {
      await _expectNoOverflowAtPhoneWidths(
        tester,
        'AnalysisScreen',
        const Scaffold(body: AnalysisScreen(embedded: true)),
        overrides: [
          analysisProvider.overrideWith(_StubAnalysisController.new),
          specTextProvider.overrideWith(_StubSpecTextController.new),
        ],
      );
    });

    testWidgets('WorkspaceReposScreen signed-out state', (tester) async {
      await _expectNoOverflowAtPhoneWidths(
        tester,
        'WorkspaceReposScreen',
        const Scaffold(body: WorkspaceReposScreen()),
        overrides: [
          neurohubTokenStorageProvider.overrideWithValue(_MemoryTokenStorage()),
          neurohubClientProvider.overrideWithValue(
            NeurohubClient(baseUrl: 'http://test'),
          ),
        ],
      );
    });

    testWidgets('HubProfileSection artefact list', (tester) async {
      await _expectNoOverflowAtPhoneWidths(
        tester,
        'HubProfileSection',
        Scaffold(
          body: SingleChildScrollView(
            child: HubProfileSection(
              title: 'Workspaces',
              kind: HubArtefactKind.workspace,
              items: kHubPreviewArtefacts,
              selectedTag: null,
              onSelect: (_) {},
              onTagSelected: (_) {},
              onToggleVisibility: (_) {},
            ),
          ),
        ),
      );
    });

    testWidgets('WorkspaceRepoCard long repo name', (tester) async {
      final repo = NeurohubWorkspaceSummary.fromJson(<String, dynamic>{
        'owner': 'alice',
        'slug': 'very-long-workspace-repo-name-that-wraps',
        'display_name': 'Very long workspace repo name that must wrap on phones',
        'description':
            'A description long enough to exercise ellipsis on narrow widths.',
        'tags': <String>['vision'],
        'private': true,
        'archived': false,
        'updated_at': '2026-01-01T00:00:00Z',
        'head_commit': 'abc',
        'repository_url': 'https://github.com/alice/repo',
        'permission': 'admin',
        'neurohub_uri': 'neurohub://studio_workspace/alice/repo',
      });
      await _expectNoOverflowAtPhoneWidths(
        tester,
        'WorkspaceRepoCard',
        Scaffold(
          body: WorkspaceRepoCard(workspace: repo, onTap: () {}),
        ),
      );
    });

    testWidgets('HubTagFilterChip selected and unselected', (tester) async {
      await _expectNoOverflowAtPhoneWidths(
        tester,
        'HubTagFilterChip',
        Scaffold(
          body: Wrap(
            children: <Widget>[
              HubTagFilterChip(
                tag: 'akida',
                selected: true,
                onChanged: (_) {},
              ),
              HubTagFilterChip(
                tag: 'vision',
                selected: false,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      );
    });

    testWidgets('ShareWorkspaceScreen keeps cancel affordance', (tester) async {
      for (final size in _phoneSizes) {
        _useViewport(tester, size);
        await tester.pumpWidget(
          _zetaApp(
            home: const ShareWorkspaceScreen(),
            overrides: [
              neurohubClientProvider.overrideWithValue(
                NeurohubClient(baseUrl: 'http://test'),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.byTooltip('Close'), findsOneWidget);
      }
    });
  });

  group('CEL-430 rendered contrast (light + dark)', () {
    for (final mode in <ThemeMode>{ThemeMode.light, ThemeMode.dark}) {
      testWidgets('WorkspaceRepoCard folder icon @ $mode', (tester) async {
        final repo = NeurohubWorkspaceSummary.fromJson(<String, dynamic>{
          'owner': 'alice',
          'slug': 'mnist',
          'display_name': 'MNIST',
          'description': '',
          'tags': <String>[],
          'private': true,
          'archived': false,
          'updated_at': '2026-01-01T00:00:00Z',
          'head_commit': 'abc',
          'repository_url': 'https://github.com/alice/mnist',
          'permission': 'write',
          'neurohub_uri': 'neurohub://studio_workspace/alice/mnist',
        });
        await tester.pumpWidget(
          ZetaProvider(
            initialContrast: ZetaContrast.aa,
            initialThemeMode: mode,
            builder: (context, light, dark, effective) => MaterialApp(
              theme: light,
              darkTheme: dark,
              themeMode: effective,
              home: Scaffold(
                body: WorkspaceRepoCard(workspace: repo, onTap: () {}),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final icon = tester.widget<Icon>(
          find.byIcon(Icons.folder_copy_outlined),
        );
        final bg = _surfaceColor(tester);
        expect(_contrastRatio(icon.color!, bg), greaterThanOrEqualTo(3.0));
      });
    }
  });

  group('CEL-430 sign-in dialog mobile surface', () {
    testWidgets('NeurohubSignInDialog shows Cancel at phone widths', (
      tester,
    ) async {
      for (final size in _phoneSizes) {
        _useViewport(tester, size);
        await tester.pumpWidget(
          _zetaApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showNeurohubSignInDialog(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
            overrides: [
              neurohubClientProvider.overrideWithValue(
                NeurohubClient(
                  baseUrl: 'http://test',
                  httpClient: MockClient((request) async {
                    if (request.url.path.endsWith('/oauth/device')) {
                      return http.Response(
                        jsonEncode({
                          'device_code': 'dev',
                          'user_code': 'ABCD-1234',
                          'verification_uri': 'https://github.com/login/device',
                          'expires_in': 900,
                          'interval': 5,
                        }),
                        200,
                      );
                    }
                    return http.Response('{}', 200);
                  }),
                ),
              ),
            ],
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('Cancel'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });
  });
}
