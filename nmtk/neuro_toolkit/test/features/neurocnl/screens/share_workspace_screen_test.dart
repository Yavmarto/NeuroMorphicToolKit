import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/neurohub_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/share_workspace_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_session_storage.dart';
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

Map<String, dynamic> _createdJson({String slug = 'mnist-akida'}) =>
    <String, dynamic>{
      'owner': 'alice',
      'slug': slug,
      'display_name': 'MNIST Akida',
      'description': '',
      'tags': <String>[],
      'private': true,
      'archived': false,
      'updated_at': '2026-08-18T00:00:00Z',
      'head_commit': 'commit-1',
      'repository_url': 'https://github.com/alice/$slug',
      'permission': 'admin',
      'neurohub_uri': 'neurohub://studio_workspace/alice/$slug',
      'workspace': const <String, dynamic>{'revision': 1, 'nodes': <dynamic>[]},
    };

/// Records the last POST body for assertions.
class _CapturedCreate {
  Map<String, dynamic>? body;
  int statusCode = 201;
}

Future<void> _pumpShare(
  WidgetTester tester, {
  required MockClient client,
  String? token = 'gh-token',
}) async {
  final storage = _MemoryTokenStorage(token);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        neurohubTokenStorageProvider.overrideWithValue(storage),
        neurohubClientProvider.overrideWithValue(
          NeurohubClient(
            baseUrl: 'http://test',
            accessToken: token,
            httpClient: client,
          ),
        ),
      ],
      child: const _Host(child: _ShareLauncher()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

class _ShareLauncher extends StatefulWidget {
  const _ShareLauncher();

  @override
  State<_ShareLauncher> createState() => _ShareLauncherState();
}

class _ShareLauncherState extends State<_ShareLauncher> {
  NeurohubWorkspace? result;

  Future<void> _open() async {
    final created = await Navigator.of(context).push<NeurohubWorkspace>(
      MaterialPageRoute<NeurohubWorkspace>(
        builder: (context) => const ShareWorkspaceScreen(),
      ),
    );
    if (created != null && mounted) {
      setState(() => result = created);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NmtkPrimaryButton(label: 'Open share', onPressed: _open),
          if (result != null) Text('Created: ${result!.slug}'),
        ],
      ),
    );
  }
}

Future<void> _openAndSubmit(WidgetTester tester, {required String name}) async {
  await tester.tap(find.text('Open share'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.byType(ShareWorkspaceScreen), findsOneWidget);

  await tester.enterText(
    find.byKey(const Key('share-workspace-name-field')),
    name,
  );
  await tester.pump();

  await tester.tap(find.byKey(const Key('share-workspace-submit')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  group('ShareWorkspaceScreen', () {
    testWidgets('submits a name and pops with the created workspace', (
      tester,
    ) async {
      final captured = _CapturedCreate();
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/neurohub/workspaces');
        expect(request.headers['Authorization'], 'Bearer gh-token');
        captured.body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_createdJson()), 201);
      });

      await _pumpShare(tester, client: client);
      await _openAndSubmit(tester, name: 'MNIST Akida');
      await tester.pump(const Duration(milliseconds: 300));

      // The server decides repo naming/topic tagging; the client only sends
      // the name-derived slug, display name, and an empty workspace document.
      expect(captured.body, isNotNull);
      expect(captured.body!['slug'], 'mnist-akida');
      expect(captured.body!['display_name'], 'MNIST Akida');
      expect(captured.body!['private'], isTrue);
      expect(captured.body!['workspace'], <String, dynamic>{
        'revision': 1,
        'nodes': <dynamic>[],
      });

      expect(find.byType(ShareWorkspaceScreen), findsNothing);
      expect(find.text('Created: mnist-akida'), findsOneWidget);
    });

    testWidgets('shows a create-failure state when the endpoint errors', (
      tester,
    ) async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'The workspace already exists'}),
          422,
        );
      });

      await _pumpShare(tester, client: client);
      await _openAndSubmit(tester, name: 'MNIST Akida');

      expect(find.byKey(const Key('share-workspace-error')), findsOneWidget);
      expect(find.text('Could not share this workspace'), findsOneWidget);
      expect(find.textContaining('already exists'), findsOneWidget);
      // The form stays open so the user can change the name and retry.
      expect(find.byType(ShareWorkspaceScreen), findsOneWidget);
      expect(
        find.byKey(const Key('share-workspace-name-field')),
        findsOneWidget,
      );
    });

    testWidgets('validates an empty name before calling the API', (
      tester,
    ) async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(jsonEncode(_createdJson()), 201);
      });

      await _pumpShare(tester, client: client);
      await tester.tap(find.text('Open share'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const Key('share-workspace-submit')));
      await tester.pump();

      expect(
        find.text('Enter a name for this workspace repo.'),
        findsOneWidget,
      );
      expect(calls, 0);
      expect(find.byType(ShareWorkspaceScreen), findsOneWidget);
    });
  });
}
