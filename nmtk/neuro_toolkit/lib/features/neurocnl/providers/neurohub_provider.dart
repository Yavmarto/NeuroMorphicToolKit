import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/services/neurohub_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_session_storage.dart';
import 'package:neuro_toolkit/features/neurocnl/services/open_external_url.dart';

enum NeurohubSessionStatus { restoring, signedOut, signedIn, error }

class NeurohubSessionState {
  const NeurohubSessionState({
    required this.status,
    this.accessToken,
    this.message,
  });

  const NeurohubSessionState.restoring()
    : this(status: NeurohubSessionStatus.restoring);

  const NeurohubSessionState.signedOut({String? message})
    : this(status: NeurohubSessionStatus.signedOut, message: message);

  const NeurohubSessionState.signedIn(String token)
    : this(status: NeurohubSessionStatus.signedIn, accessToken: token);

  final NeurohubSessionStatus status;
  final String? accessToken;
  final String? message;

  bool get isSignedIn =>
      status == NeurohubSessionStatus.signedIn && accessToken != null;
}

final neurohubTokenStorageProvider = Provider<NeurohubTokenStorage>((ref) {
  return const PlatformNeurohubTokenStorage();
});

class _PlatformExternalLinkLauncher implements NeurohubExternalLinkLauncher {
  const _PlatformExternalLinkLauncher();

  @override
  Future<bool> open(String url) => openExternalUrl(url);
}

final neurohubExternalLinkLauncherProvider =
    Provider<NeurohubExternalLinkLauncher>((ref) {
      return const _PlatformExternalLinkLauncher();
    });

final neurohubSessionProvider =
    NotifierProvider<NeurohubSessionController, NeurohubSessionState>(
      NeurohubSessionController.new,
    );

class NeurohubSessionController extends Notifier<NeurohubSessionState> {
  late final Future<void> _restoration;

  @override
  NeurohubSessionState build() {
    _restoration = Future<void>.microtask(_restore);
    unawaited(_restoration);
    return const NeurohubSessionState.restoring();
  }

  /// Waits until the platform secure store has restored the previous session.
  Future<void> waitForRestoration() => _restoration;

  Future<void> _restore() async {
    try {
      final token = await ref.read(neurohubTokenStorageProvider).read();
      state = token == null || token.isEmpty
          ? const NeurohubSessionState.signedOut()
          : NeurohubSessionState.signedIn(token);
    } catch (_) {
      state = const NeurohubSessionState.signedOut(
        message: 'Your saved Neurohub sign-in could not be restored.',
      );
    }
  }

  Future<void> completeSignIn(String token) async {
    await ref.read(neurohubTokenStorageProvider).write(token);
    state = NeurohubSessionState.signedIn(token);
  }

  Future<void> signOut({String? message}) async {
    await ref.read(neurohubTokenStorageProvider).delete();
    state = NeurohubSessionState.signedOut(message: message);
  }
}

final neurohubClientProvider = Provider<NeurohubClient>((ref) {
  final token = ref.watch(
    neurohubSessionProvider.select((session) => session.accessToken),
  );
  final client = NeurohubClient(accessToken: token);
  ref.onDispose(client.dispose);
  return client;
});

final neurohubWorkspacesProvider =
    FutureProvider<List<NeurohubWorkspaceSummary>>((ref) async {
      final session = ref.read(neurohubSessionProvider);
      if (!session.isSignedIn) return const <NeurohubWorkspaceSummary>[];
      try {
        return await ref.read(neurohubClientProvider).listWorkspaces();
      } on NeurohubException catch (error) {
        if (error.statusCode == 401) {
          await ref
              .read(neurohubSessionProvider.notifier)
              .signOut(
                message: 'Your Neurohub sign-in expired. Sign in again.',
              );
        }
        rethrow;
      }
    });

final neurohubWorkspaceProvider =
    FutureProvider.family<NeurohubWorkspace, ({String owner, String slug})>((
      ref,
      key,
    ) async {
      return ref.read(neurohubClientProvider).getWorkspace(key.owner, key.slug);
    });

class NeurohubWorkspaceBinding {
  const NeurohubWorkspaceBinding({
    required this.owner,
    required this.slug,
    required this.headRevision,
    required this.permission,
  });

  final String owner;
  final String slug;
  final String headRevision;
  final String permission;

  bool get canEdit => permission == 'write' || permission == 'admin';
  bool get canManage => permission == 'admin';

  NeurohubWorkspaceBinding copyWith({String? headRevision}) {
    return NeurohubWorkspaceBinding(
      owner: owner,
      slug: slug,
      headRevision: headRevision ?? this.headRevision,
      permission: permission,
    );
  }

  factory NeurohubWorkspaceBinding.fromWorkspace(
    NeurohubWorkspaceSummary workspace,
  ) {
    return NeurohubWorkspaceBinding(
      owner: workspace.owner,
      slug: workspace.slug,
      headRevision: workspace.headCommit,
      permission: workspace.permission,
    );
  }
}

final neurohubWorkspaceBindingProvider =
    NotifierProvider<
      NeurohubWorkspaceBindingController,
      NeurohubWorkspaceBinding?
    >(NeurohubWorkspaceBindingController.new);

class NeurohubWorkspaceBindingController
    extends Notifier<NeurohubWorkspaceBinding?> {
  @override
  NeurohubWorkspaceBinding? build() => null;

  void bind(NeurohubWorkspaceSummary workspace) {
    state = NeurohubWorkspaceBinding.fromWorkspace(workspace);
  }

  void updateRevision(String revision) {
    state = state?.copyWith(headRevision: revision);
  }

  void clear() => state = null;
}
