import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical;
import 'package:neuro_toolkit/features/neurocnl/providers/neurohub_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/neurohub_sign_in_dialog.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/neurohub_workspace_preview.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/neurohub_workspace_save.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub_popup.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_session_storage.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/workspace_file.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

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

class _LinkLauncher implements NeurohubExternalLinkLauncher {
  String? opened;

  @override
  Future<bool> open(String url) async {
    opened = url;
    return true;
  }
}

NeurohubWorkspace _workspace({String permission = 'admin'}) {
  final payload = _workspacePayload();
  return NeurohubWorkspace(
    owner: permission == 'admin' ? 'maya' : 'ravi',
    slug: permission == 'admin' ? 'gesture-model' : 'shared-model',
    displayName: permission == 'admin' ? 'Gesture model' : 'Shared model',
    description: 'A real workspace from Neurohub.',
    tags: const <String>['vision'],
    private: permission == 'admin',
    archived: false,
    updatedAt: '2026-08-20T08:00:00Z',
    headCommit: 'revision-1',
    repositoryUrl: 'https://example.invalid/workspace',
    permission: permission,
    neurohubUri: 'neurohub://studio_workspace/example/workspace',
    workspace: payload,
  );
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
    workspaceName: 'Preview workspace',
  );
  return <String, dynamic>{
    'version': 1,
    'workspace': workspace.toJson(),
    'canvas': <String, dynamic>{'pipelinePhases': <String, dynamic>{}},
  };
}

class _FakeNeurohubClient extends NeurohubClient {
  _FakeNeurohubClient({this.deviceFlow = false})
    : super(baseUrl: 'http://test');

  final bool deviceFlow;
  final managed = _workspace();
  final shared = _workspace(permission: 'read');
  int starts = 0;
  int polls = 0;

  @override
  Future<NeurohubDeviceFlowConfig> oauthConfig() async =>
      const NeurohubDeviceFlowConfig(clientId: 'client', scopes: <String>[]);

  @override
  Future<NeurohubDeviceCodeStarted> startDeviceAuthorization() async {
    starts++;
    return const NeurohubDeviceCodeStarted(
      sessionId: 'session',
      userCode: 'ABCD-1234',
      verificationUri: 'https://github.com/login/device',
      expiresIn: 900,
      interval: 1,
    );
  }

  @override
  Future<NeurohubDevicePollResult> pollDeviceAuthorization(
    String sessionId,
  ) async {
    polls++;
    return const NeurohubDevicePollResult(
      status: 'success',
      accessToken: 'signed-in-token',
    );
  }

  @override
  Future<List<NeurohubWorkspaceSummary>> listWorkspaces() async =>
      <NeurohubWorkspaceSummary>[managed, shared];

  @override
  Future<NeurohubWorkspace> getWorkspace(String owner, String slug) async =>
      owner == managed.owner ? managed : shared;
}

class _ExpiredSessionClient extends _FakeNeurohubClient {
  bool rejectedSavedToken = false;

  @override
  Future<List<NeurohubWorkspaceSummary>> listWorkspaces() async {
    if (!rejectedSavedToken) {
      rejectedSavedToken = true;
      throw const NeurohubException(401, 'expired');
    }
    return super.listWorkspaces();
  }
}

class _ConflictClient extends _FakeNeurohubClient {
  int copies = 0;

  @override
  Future<NeurohubWorkspace> updateWorkspace(
    String owner,
    String slug, {
    required String baseCommit,
    required Map<String, dynamic> workspace,
    String? displayName,
    String? description,
    List<String>? tags,
    String message = 'Save workspace',
  }) async {
    throw const NeurohubConflictException(
      baseCommit: 'revision-1',
      remoteCommit: 'revision-2',
      recovery: <String>['reload', 'save_copy', 'resolve'],
    );
  }

  @override
  Future<NeurohubWorkspace> createWorkspace({
    required String slug,
    required String displayName,
    required Map<String, dynamic> workspace,
    String description = '',
    List<String> tags = const <String>[],
    bool private = true,
  }) async {
    copies++;
    return NeurohubWorkspace(
      owner: 'maya',
      slug: slug,
      displayName: displayName,
      description: description,
      tags: tags,
      private: private,
      archived: false,
      updatedAt: '2026-08-20T09:00:00Z',
      headCommit: 'copy-revision',
      repositoryUrl: 'https://example.invalid/copy',
      permission: 'admin',
      neurohubUri: 'neurohub://studio_workspace/maya/$slug',
      workspace: workspace,
    );
  }
}

class _Host extends StatelessWidget {
  const _Host({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ZetaProvider(
      initialContrast: ZetaContrast.aa,
      initialThemeMode: ThemeMode.dark,
      builder: (context, light, dark, mode) => MaterialApp(
        theme: light,
        darkTheme: dark,
        themeMode: mode,
        home: Scaffold(body: child),
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required _MemoryTokenStorage storage,
  required NeurohubClient client,
  NeurohubExternalLinkLauncher? launcher,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        neurohubTokenStorageProvider.overrideWithValue(storage),
        neurohubClientProvider.overrideWithValue(client),
        if (launcher != null)
          neurohubExternalLinkLauncherProvider.overrideWithValue(launcher),
      ],
      child: _Host(child: child),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  test('workspace preview data parses the portable payload', () {
    final data = NeurohubWorkspacePreviewData.fromPayload(_workspacePayload());
    expect(data.model.nodes, hasLength(2));
  });

  testWidgets(
    'device sign-in shows code, opens the link, and persists success',
    (tester) async {
      final storage = _MemoryTokenStorage();
      final launcher = _LinkLauncher();
      final client = _FakeNeurohubClient(deviceFlow: true);
      await _pump(
        tester,
        Builder(
          builder: (context) => Center(
            child: NmtkPrimaryButton(
              label: 'Open sign-in',
              onPressed: () => showNeurohubSignInDialog(context),
            ),
          ),
        ),
        storage: storage,
        client: client,
        launcher: launcher,
      );

      await tester.tap(find.text('Open sign-in'));
      await tester.pump();
      await tester.pump();
      expect(find.text('ABCD-1234'), findsOneWidget);

      await tester.tap(find.byKey(const Key('neurohub-open-sign-in-link')));
      await tester.pump();
      expect(launcher.opened, 'https://github.com/login/device');

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(storage.token, 'signed-in-token');
      expect(client.polls, 1);
      expect(find.byType(NeurohubSignInDialog), findsNothing);
    },
  );

  testWidgets('profile entry signs in before opening managed workspaces', (
    tester,
  ) async {
    final storage = _MemoryTokenStorage();
    final client = _FakeNeurohubClient(deviceFlow: true);
    await _pump(
      tester,
      Builder(
        builder: (context) => NmtkPrimaryButton(
          label: 'Open profile',
          onPressed: () =>
              showHubPopup(context, intent: HubPopupIntent.profile),
        ),
      ),
      storage: storage,
      client: client,
    );

    await tester.tap(find.text('Open profile'));
    await tester.pump();
    expect(find.byType(NeurohubSignInDialog), findsOneWidget);
    expect(find.byType(HubPopup), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byType(NeurohubSignInDialog), findsNothing);
    expect(find.byType(HubPopup), findsOneWidget);
    expect(find.text('Gesture model'), findsOneWidget);
  });

  testWidgets('load-from-Hub entry signs in before opening shared workspaces', (
    tester,
  ) async {
    final storage = _MemoryTokenStorage();
    final client = _FakeNeurohubClient(deviceFlow: true);
    await _pump(
      tester,
      Builder(
        builder: (context) => NmtkPrimaryButton(
          label: 'Load from Hub',
          onPressed: () =>
              showHubPopup(context, intent: HubPopupIntent.workspaces),
        ),
      ),
      storage: storage,
      client: client,
    );

    await tester.tap(find.text('Load from Hub'));
    await tester.pump();
    expect(find.byType(NeurohubSignInDialog), findsOneWidget);
    expect(find.byType(HubPopup), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byType(HubPopup), findsOneWidget);
    expect(find.text('Shared model'), findsOneWidget);
  });

  testWidgets('Hub entry checks a saved session and signs in when it expired', (
    tester,
  ) async {
    final storage = _MemoryTokenStorage('expired-token');
    final client = _ExpiredSessionClient();
    await _pump(
      tester,
      Builder(
        builder: (context) => NmtkPrimaryButton(
          label: 'Open profile',
          onPressed: () => showHubPopup(context),
        ),
      ),
      storage: storage,
      client: client,
    );

    await tester.tap(find.text('Open profile'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(client.rejectedSavedToken, isTrue);
    expect(client.starts, 1);
    expect(find.byType(NeurohubSignInDialog), findsOneWidget);
    expect(storage.token, isNull);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byType(HubPopup), findsOneWidget);
    expect(storage.token, 'signed-in-token');
  });

  testWidgets('Hub entry keeps a valid restored session without prompting', (
    tester,
  ) async {
    final storage = _MemoryTokenStorage('valid-token');
    final client = _FakeNeurohubClient();
    await _pump(
      tester,
      Builder(
        builder: (context) => NmtkPrimaryButton(
          label: 'Open profile',
          onPressed: () => showHubPopup(context),
        ),
      ),
      storage: storage,
      client: client,
    );

    await tester.tap(find.text('Open profile'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(HubPopup), findsOneWidget);
    expect(find.byType(NeurohubSignInDialog), findsNothing);
    expect(client.starts, 0);
  });

  testWidgets('Hub renders real managed and shared workspace data', (
    tester,
  ) async {
    final storage = _MemoryTokenStorage('token');
    final client = _FakeNeurohubClient();
    await _pump(
      tester,
      const HubPopup(intent: HubPopupIntent.profile),
      storage: storage,
      client: client,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('Gesture model'), findsOneWidget);
    expect(find.text('Shared model'), findsNothing);
    expect(find.text('Maya Chen'), findsNothing);

    await tester.tap(find.text('Gesture model'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byKey(const Key('neurohub-read-only-canvas')), findsOneWidget);
    expect(find.text('Fork a copy'), findsOneWidget);

    final visibleCopy = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join(' ')
        .toLowerCase();
    for (final forbidden in <String>[
      'commit',
      'sha',
      'merge',
      'clone',
      'push',
    ]) {
      expect(visibleCopy, isNot(contains(forbidden)));
    }
  });

  testWidgets('read-only preview renders without requiring Studio providers', (
    tester,
  ) async {
    final storage = _MemoryTokenStorage('token');
    await _pump(
      tester,
      SizedBox(
        width: 900,
        height: 600,
        child: NeurohubWorkspacePreview(payload: _workspacePayload()),
      ),
      storage: storage,
      client: _FakeNeurohubClient(),
    );

    expect(find.byKey(const Key('neurohub-read-only-canvas')), findsOneWidget);
    expect(find.text('Model'), findsOneWidget);
    expect(find.text('Train'), findsOneWidget);
    expect(find.text('Evaluate'), findsOneWidget);
  });

  testWidgets('save conflict compares without replacing local work', (
    tester,
  ) async {
    final storage = _MemoryTokenStorage('token');
    final client = _ConflictClient();
    var reloaded = false;
    await _pump(
      tester,
      Consumer(
        builder: (context, ref, _) => Center(
          child: NmtkPrimaryButton(
            label: 'Save cloud',
            onPressed: () => saveCurrentWorkspaceToNeurohub(
              context,
              ref,
              payload: _workspacePayload(),
              workspaceName: 'Gesture model',
              reloadWorkspace: (_) async => reloaded = true,
            ),
          ),
        ),
      ),
      storage: storage,
      client: client,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.text('Save cloud')),
    );
    await container
        .read(neurohubSessionProvider.notifier)
        .completeSignIn('token');
    container
        .read(neurohubWorkspaceBindingProvider.notifier)
        .bind(client.managed);

    await tester.tap(find.text('Save cloud'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('This workspace changed elsewhere'), findsOneWidget);
    expect(find.text('Reload saved version'), findsOneWidget);
    expect(find.text('Save as new workspace'), findsOneWidget);

    await tester.tap(find.text('Compare changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('Your Studio workspace'), findsOneWidget);
    expect(find.text('Latest saved workspace'), findsOneWidget);

    await tester.tap(find.text('Keep editing').last);
    await tester.pump();
    expect(reloaded, isFalse);
    expect(client.copies, 0);
    expect(find.text('Save cloud'), findsOneWidget);
  });
}
