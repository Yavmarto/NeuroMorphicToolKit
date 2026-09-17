import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/neurohub_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_session_storage.dart';

class _MemoryTokenStorage implements NeurohubTokenStorage {
  _MemoryTokenStorage([this.token]);

  String? token;
  int writes = 0;
  int deletes = 0;

  @override
  Future<void> delete() async {
    deletes++;
    token = null;
  }

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async {
    writes++;
    this.token = token;
  }
}

class _WorkspaceClient extends NeurohubClient {
  _WorkspaceClient({this.error}) : super(baseUrl: 'http://test');

  final NeurohubException? error;

  @override
  Future<List<NeurohubWorkspaceSummary>> listWorkspaces() async {
    if (error case final error?) throw error;
    return const <NeurohubWorkspaceSummary>[];
  }
}

Future<void> _settleProvider() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test(
    'restores the saved token and rebuilds the client after sign-in',
    () async {
      final storage = _MemoryTokenStorage('saved-token');
      final container = ProviderContainer(
        overrides: [neurohubTokenStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(neurohubSessionProvider).status,
        NeurohubSessionStatus.restoring,
      );
      await _settleProvider();
      expect(
        container.read(neurohubSessionProvider).accessToken,
        'saved-token',
      );

      final firstClient = container.read(neurohubClientProvider);
      await container
          .read(neurohubSessionProvider.notifier)
          .completeSignIn('new-token');
      final secondClient = container.read(neurohubClientProvider);

      expect(storage.token, 'new-token');
      expect(storage.writes, 1);
      expect(secondClient, isNot(same(firstClient)));
      expect(secondClient.accessToken, 'new-token');
    },
  );

  test('sign-out deletes the secure token', () async {
    final storage = _MemoryTokenStorage('saved-token');
    final container = ProviderContainer(
      overrides: [neurohubTokenStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    container.read(neurohubSessionProvider);
    await _settleProvider();

    await container.read(neurohubSessionProvider.notifier).signOut();

    expect(storage.token, isNull);
    expect(storage.deletes, 1);
    expect(
      container.read(neurohubSessionProvider).status,
      NeurohubSessionStatus.signedOut,
    );
  });

  test(
    'an unauthorized workspace response clears an expired session',
    () async {
      final storage = _MemoryTokenStorage('expired-token');
      final client = _WorkspaceClient(
        error: const NeurohubException(401, 'expired'),
      );
      final container = ProviderContainer(
        overrides: [
          neurohubTokenStorageProvider.overrideWithValue(storage),
          neurohubClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);
      container.read(neurohubSessionProvider);
      await _settleProvider();
      await container
          .read(neurohubSessionProvider.notifier)
          .completeSignIn('expired-token');
      final subscription = container.listen(
        neurohubWorkspacesProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      expect(await container.read(neurohubWorkspacesProvider.future), isEmpty);

      expect(storage.token, isNull);
      expect(
        container.read(neurohubSessionProvider).message,
        contains('expired'),
      );
    },
  );
}
