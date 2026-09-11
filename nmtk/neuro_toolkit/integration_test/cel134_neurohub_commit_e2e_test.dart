import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical;
import 'package:neuro_toolkit/features/neurocnl/providers/neurohub_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub_popup.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/neurohub_workspace_save.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_session_storage.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/workspace_file.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// CEL-134: end-to-end Neurohub "connect → list → create → commit" flow.
///
/// Drives the real sign-in dialog, Hub workspace browser, and commit/save
/// flow against a fake Neurohub API transport (same in-memory-fake pattern the
/// backend uses in `Neurohub/neurohub/tests/test_github_workspace_store.py`),
/// so it runs on-device with no live GitHub credentials:
///
///   cd nmtk/neuro_toolkit
///   flutter test integration_test/cel134_neurohub_commit_e2e_test.dart -d macos
///
/// Sequence:
///   1. connect  — device-flow sign-in via the save entry point
///   2. list     — Hub popup lists the signed-in user's workspaces
///   3. create   — first save creates a private workspace repo
///   4. commit   — second save pushes one atomic revision (base_commit)
///   5. conflict — a stale save surfaces the real conflict UI
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> waitForText(
    WidgetTester tester,
    String text, {
    int seconds = 10,
  }) async {
    for (var i = 0; i < seconds * 4; i++) {
      if (find.text(text).evaluate().isNotEmpty) return;
      await tester.pump(const Duration(milliseconds: 250));
    }
    throw TestFailure('timed out waiting for text "$text"');
  }

  testWidgets('Neurohub connect, list, create, commit, conflict end-to-end', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final backend = _FakeNeurohubBackend();
    final storage = _MemoryTokenStorage();
    final launcher = _FakeLinkLauncher();
    final client = NeurohubClient(
      baseUrl: 'http://test',
      httpClient: MockClient(backend.handle),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          neurohubTokenStorageProvider.overrideWithValue(storage),
          neurohubClientProvider.overrideWithValue(client),
          neurohubExternalLinkLauncherProvider.overrideWithValue(launcher),
        ],
        child: ZetaProvider(
          initialContrast: ZetaContrast.aa,
          initialThemeMode: ThemeMode.dark,
          builder: (context, light, dark, mode) => MaterialApp(
            theme: light,
            darkTheme: dark,
            themeMode: mode,
            home: const _E2EHarness(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ── 1. connect: device-flow sign-in, launched from the save entry. ──
    await tester.tap(find.byKey(const Key('e2e-save-to-neurohub')));
    await tester.pumpAndSettle();
    // The device-flow poll completes in-test, so sign-in ends on the first
    // save flow and the flow continues straight into the create dialog.
    expect(storage.token, 'gh-token');
    expect(backend.requests, contains('POST /api/neurohub/oauth/device/poll'));
    expect(find.text('Workspace name'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // ── 2. list: Hub popup shows the signed-in user's workspaces. ──
    await tester.tap(find.byKey(const Key('e2e-browse-hub')));
    await tester.pumpAndSettle();
    expect(find.text('Shared model'), findsOneWidget);
    expect(backend.requests, contains('GET /api/neurohub/workspaces'));
    expect(backend.requests, contains('GET /api/neurohub/workspaces'));
    await tester.tap(find.byTooltip('Close NeuroHub'));
    await tester.pumpAndSettle();

    // ── 3. create: first save creates a private workspace repo. ──
    await tester.tap(find.byKey(const Key('e2e-save-to-neurohub')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('neurohub-create-name')),
      'E2E workspace',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('neurohub-create-save')));
    await tester.pumpAndSettle();
    await waitForText(tester, 'Saved privately to Neurohub.');
    expect(
      backend.requests,
      contains('POST /api/neurohub/workspaces'),
      reason: 'first save must create the workspace repo.',
    );
    expect(backend.createdSlug, 'e2e-workspace');

    // ── 4. commit: second save pushes one atomic revision. ──
    await tester.tap(find.byKey(const Key('e2e-save-to-neurohub')));
    await tester.pumpAndSettle();
    await waitForText(tester, 'Saved to Neurohub.');
    final updateCall = backend.requests
        .where((r) => r.startsWith('PUT /api/neurohub/workspaces/'))
        .toList();
    expect(
      updateCall,
      hasLength(1),
      reason: 'a bound workspace saves via the atomic update endpoint.',
    );
    expect(
      backend.lastUpdateBaseCommit,
      backend.createdHeadCommit,
      reason: 'the commit must carry the base commit it was saved from.',
    );

    // ── 5. conflict: a stale save surfaces the real conflict UI. ──
    backend.conflictOnUpdate = true;
    await tester.tap(find.byKey(const Key('e2e-save-to-neurohub')));
    await tester.pumpAndSettle();
    await waitForText(tester, 'This workspace changed elsewhere');
    expect(find.text('Reload saved version'), findsOneWidget);
    expect(find.text('Save as new workspace'), findsOneWidget);
    await tester.tap(find.text('Keep editing').last);
    await tester.pumpAndSettle();
    expect(find.text('This workspace changed elsewhere'), findsNothing);

    // The list now includes the newly created workspace.
    await tester.tap(find.byKey(const Key('e2e-browse-hub')));
    await tester.pumpAndSettle();
    expect(find.text('Shared model'), findsOneWidget);
    expect(find.text('E2E workspace'), findsOneWidget);
  });
}

class _MemoryTokenStorage implements NeurohubTokenStorage {
  String? token;

  @override
  Future<void> delete() async => token = null;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async => this.token = token;
}

class _FakeLinkLauncher implements NeurohubExternalLinkLauncher {
  String? opened;

  @override
  Future<bool> open(String url) async {
    opened = url;
    return true;
  }
}

/// In-memory Neurohub API boundary, mirroring the workspace-store contract
/// (`Neurohub/neurohub/contracts/workspace_contracts.py`).
class _FakeNeurohubBackend {
  _FakeNeurohubBackend() {
    workspaces.add(
      _full(
        owner: 'Maya Chen',
        slug: 'shared-model',
        displayName: 'Shared model',
        head: 'seed-commit',
        workspace: const <String, dynamic>{'revision': 1},
      ),
    );
  }

  int _commitCount = 0;
  bool conflictOnUpdate = false;
  final List<String> requests = <String>[];
  final List<Map<String, dynamic>> workspaces = <Map<String, dynamic>>[];

  String? createdSlug;
  String? createdHeadCommit;
  String? lastUpdateBaseCommit;

  http.Response _json(int status, Object body) {
    return http.Response(
      jsonEncode(body),
      status,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }

  Map<String, dynamic> _summary({
    required String owner,
    required String slug,
    required String displayName,
    required String head,
  }) {
    return <String, dynamic>{
      'owner': owner,
      'slug': slug,
      'display_name': displayName,
      'description': '',
      'tags': <String>[],
      'private': true,
      'archived': false,
      'updated_at': '2026-09-09T08:00:00Z',
      'head_commit': head,
      'repository_url': 'https://github.com/$owner/$slug',
      'permission': 'admin',
      'neurohub_uri': 'neurohub://studio_workspace/$owner/$slug',
    };
  }

  Map<String, dynamic> _full({
    required String owner,
    required String slug,
    required String displayName,
    required String head,
    required Map<String, dynamic> workspace,
  }) {
    return <String, dynamic>{
      ..._summary(
        owner: owner,
        slug: slug,
        displayName: displayName,
        head: head,
      ),
      'workspace': workspace,
      'manifest': <String, dynamic>{
        'slug': slug,
        'display_name': displayName,
        'description': '',
        'tags': <String>[],
        'payload': <String, dynamic>{'sha256': 'test'},
        'nmtk': <String, String>{},
      },
    };
  }

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    final method = request.method;
    requests.add('$method $path');

    if (path.endsWith('/oauth/config')) {
      return _json(200, <String, dynamic>{
        'client_id': 'e2e-client',
        'scopes': <String>['repo', 'read:user'],
      });
    }
    if (path.endsWith('/oauth/device/start')) {
      return _json(200, <String, dynamic>{
        'session_id': 'session-1',
        'user_code': 'ABCD-EFGH',
        'verification_uri': 'https://github.com/login/device',
        'expires_in': 900,
        'interval': 0,
      });
    }
    if (path.endsWith('/oauth/device/poll')) {
      return _json(200, <String, dynamic>{
        'status': 'success',
        'access_token': 'gh-token',
      });
    }
    if (method == 'GET' && path.endsWith('/workspaces')) {
      return _json(200, <Object>[
        for (final workspace in workspaces)
          _summary(
            owner: workspace['owner'] as String,
            slug: workspace['slug'] as String,
            displayName: workspace['display_name'] as String,
            head: workspace['head_commit'] as String,
          ),
      ]);
    }
    if (method == 'POST' && path.endsWith('/workspaces')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final slug = body['slug'] as String;
      final displayName = body['display_name'] as String;
      _commitCount++;
      final head = 'commit-$_commitCount';
      createdSlug = slug;
      createdHeadCommit = head;
      final workspace = Map<String, dynamic>.from(body['workspace'] as Map);
      final full = _full(
        owner: 'Maya Chen',
        slug: slug,
        displayName: displayName,
        head: head,
        workspace: workspace,
      );
      workspaces.add(full);
      return _json(201, full);
    }

    final segments = request.url.pathSegments;
    if (segments.length == 5 &&
        segments[0] == 'api' &&
        segments[1] == 'neurohub' &&
        segments[2] == 'workspaces') {
      final owner = Uri.decodeComponent(segments[3]);
      final slug = segments[4];
      Map<String, dynamic>? existing;
      for (final workspace in workspaces) {
        if (workspace['owner'] == owner && workspace['slug'] == slug) {
          existing = workspace;
          break;
        }
      }
      if (existing == null) {
        return _json(404, <String, dynamic>{'detail': 'not found'});
      }
      if (method == 'GET') {
        return _json(200, existing);
      }
      if (method == 'PUT') {
        if (conflictOnUpdate) {
          return _json(409, <String, dynamic>{
            'detail': <String, dynamic>{
              'code': 'workspace_conflict',
              'base_commit': existing['head_commit'],
              'remote_commit': 'commit-99',
              'recovery': <String>['reload', 'save_copy', 'resolve'],
            },
          });
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        lastUpdateBaseCommit = body['base_commit'] as String;
        _commitCount++;
        existing['head_commit'] = 'commit-$_commitCount';
        existing['workspace'] = body['workspace'];
        existing['updated_at'] = '2026-09-09T09:00:00Z';
        return _json(200, existing);
      }
    }
    return _json(404, <String, dynamic>{'detail': 'unknown route'});
  }
}

Map<String, dynamic> _workspacePayload() {
  const document = canonical.CanonicalEditorDocument(
    irJson: <String, dynamic>{},
    canvas: canonical.CanvasProjection(
      nodes: <canonical.CanvasNode>[
        canonical.CanvasNode(id: 'input', label: 'Input'),
        canonical.CanvasNode(id: 'lif', label: 'LIF population'),
      ],
      edges: <canonical.CanvasEdge>[
        canonical.CanvasEdge(source: 'input', target: 'lif'),
      ],
    ),
  );
  const workspace = WorkspaceState(
    files: <WorkspaceFile>[
      WorkspaceFile(
        id: 'model',
        name: 'model.cnl',
        canonicalDocument: document,
      ),
    ],
    activeFileId: 'model',
    workspaceName: 'E2E workspace',
  );
  return <String, dynamic>{
    'version': 1,
    'workspace': workspace.toJson(),
    'canvas': <String, dynamic>{'pipelinePhases': <String, dynamic>{}},
  };
}

class _E2EHarness extends ConsumerWidget {
  const _E2EHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            NmtkPrimaryButton(
              key: const Key('e2e-save-to-neurohub'),
              label: 'Save to Neurohub',
              onPressed: () => saveCurrentWorkspaceToNeurohub(
                context,
                ref,
                payload: _workspacePayload(),
                workspaceName: 'E2E workspace',
                reloadWorkspace: (_) async {},
              ),
            ),
            NmtkOutlinedButton(
              key: const Key('e2e-browse-hub'),
              label: 'Browse Hub',
              onPressed: () =>
                  showHubPopup(context, intent: HubPopupIntent.profile),
            ),
          ],
        ),
      ),
    );
  }
}
