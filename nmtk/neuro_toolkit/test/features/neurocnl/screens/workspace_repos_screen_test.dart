import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/neurohub_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/share_workspace_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/workspace_repos_screen.dart';
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

Map<String, dynamic> _repoJson({
  String owner = 'alice',
  String slug = 'mnist-akida',
  String displayName = 'MNIST Akida',
  String permission = 'admin',
  Map<String, dynamic>? workspace,
}) => <String, dynamic>{
  'owner': owner,
  'slug': slug,
  'display_name': displayName,
  'description': '',
  'tags': <String>[],
  'private': true,
  'archived': false,
  'updated_at': '2026-08-18T00:00:00Z',
  'head_commit': 'commit-1',
  'repository_url': 'https://github.com/$owner/$slug',
  'permission': permission,
  'neurohub_uri': 'neurohub://studio_workspace/$owner/$slug',
  'workspace': ?workspace,
};

/// HTTP client for the list screen: a GET on `/api/neurohub/workspaces` and
/// an optional POST that creates a repo.
MockClient _reposClient({
  required List<Map<String, dynamic>> Function() list,
  Map<String, dynamic>? created,
  int listStatus = 200,
  int? failLists,
}) {
  var listCalls = 0;
  return MockClient((request) async {
    if (request.method == 'POST' &&
        request.url.path == '/api/neurohub/workspaces') {
      return http.Response(jsonEncode(created ?? _repoJson()), 201);
    }
    if (request.method == 'GET' &&
        request.url.path == '/api/neurohub/workspaces') {
      listCalls++;
      if (failLists != null && listCalls <= failLists) {
        return http.Response(
          jsonEncode({'detail': 'GitHub is down'}),
          listStatus,
        );
      }
      return http.Response(jsonEncode(list()), 200);
    }
    return http.Response('{"detail":"unexpected"}', 404);
  });
}

Future<void> _pumpRepos(
  WidgetTester tester, {
  required http.Client client,
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
      child: const _Host(child: WorkspaceReposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  group('WorkspaceReposScreen', () {
    testWidgets('renders the already-filtered workspace repo list', (
      tester,
    ) async {
      final client = _reposClient(
        list: () => [
          _repoJson(slug: 'mnist-akida', displayName: 'MNIST Akida'),
          _repoJson(
            slug: 'workspace-gesture',
            displayName: 'Gesture model',
            permission: 'write',
          ),
        ],
      );
      await _pumpRepos(tester, client: client);

      expect(find.text('My workspace repos'), findsOneWidget);
      expect(find.text('MNIST Akida'), findsOneWidget);
      expect(find.text('alice/mnist-akida'), findsOneWidget);
      expect(find.text('Gesture model'), findsOneWidget);
      expect(find.text('alice/workspace-gesture'), findsOneWidget);
      expect(
        find.byKey(const Key('share-new-workspace-repo-button')),
        findsOneWidget,
      );
    });

    testWidgets('shows an empty state when the user has no workspace repos', (
      tester,
    ) async {
      final client = _reposClient(list: () => <Map<String, dynamic>>[]);
      await _pumpRepos(tester, client: client);

      expect(find.byKey(const Key('workspace-repos-empty')), findsOneWidget);
      expect(find.text('No workspace repos yet'), findsOneWidget);
      expect(
        find.byKey(const Key('workspace-repos-empty-share')),
        findsOneWidget,
      );
    });

    testWidgets('shows an error state and recovers on retry', (tester) async {
      final client = _reposClient(
        list: () => [_repoJson()],
        failLists: 1,
        listStatus: 500,
      );
      await _pumpRepos(tester, client: client);

      expect(find.byKey(const Key('workspace-repos-error')), findsOneWidget);
      expect(find.text('Could not load your workspace repos'), findsOneWidget);
      expect(find.text('MNIST Akida'), findsNothing);

      await tester.tap(find.byKey(const Key('workspace-repos-retry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byKey(const Key('workspace-repos-error')), findsNothing);
      expect(find.text('MNIST Akida'), findsOneWidget);
    });

    testWidgets('prompts to connect GitHub when signed out', (tester) async {
      final client = _reposClient(list: () => <Map<String, dynamic>>[]);
      await _pumpRepos(tester, client: client, token: null);

      expect(find.text('Connect GitHub to share workspaces'), findsOneWidget);
      expect(
        find.byKey(const Key('workspace-repos-connect-github')),
        findsOneWidget,
      );
    });

    testWidgets(
      'opens the share screen and shows the newly created repo in the list',
      (tester) async {
        var listReturnedCreated = false;
        final client = _reposClient(
          list: () {
            if (!listReturnedCreated) {
              return <Map<String, dynamic>>[];
            }
            return [
              _repoJson(
                slug: 'mnist-akida',
                displayName: 'MNIST Akida',
                workspace: const <String, dynamic>{
                  'revision': 1,
                  'nodes': <dynamic>[],
                },
              ),
            ];
          },
          created: _repoJson(
            slug: 'mnist-akida',
            displayName: 'MNIST Akida',
            workspace: const <String, dynamic>{
              'revision': 1,
              'nodes': <dynamic>[],
            },
          ),
        );
        await _pumpRepos(tester, client: client);

        expect(find.byKey(const Key('workspace-repos-empty')), findsOneWidget);

        // Every fetch after the initial empty load returns the created repo.
        listReturnedCreated = true;

        await tester.tap(find.byKey(const Key('workspace-repos-empty-share')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(ShareWorkspaceScreen), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('share-workspace-name-field')),
          'MNIST Akida',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('share-workspace-submit')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        // The created repo pops back to the list, which refreshes and shows it.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 16));

        expect(find.byType(ShareWorkspaceScreen), findsNothing);
        expect(find.text('MNIST Akida'), findsOneWidget);
        expect(find.byKey(const Key('workspace-repos-empty')), findsNothing);
      },
    );
  });
}
