import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/server/connect/connect_service.dart';
import 'package:neuro_toolkit/features/server/shared/target_store.dart';

enum ConnectPhase { idle, reconnecting, connected, failed }

/// What the connect form submits: an app username against a host, with a
/// credential that is a password today. The shape leaves room for a passkey
/// variant later without a second method — same reasoning as the backend's
/// `{username, credential}` login endpoint (see the CEL-25 plan document).
class ConnectRequest {
  const ConnectRequest({
    required this.host,
    required this.appUsername,
    required this.credential,
  });

  final String host;
  final String appUsername;
  final String credential;
}

class ConnectState {
  const ConnectState({
    this.phase = ConnectPhase.idle,
    this.session,
    this.failureCause,
    this.savedHost,
  });

  final ConnectPhase phase;
  final ConnectSession? session;
  final String? failureCause;

  /// The last saved target's host, for prefilling the connect form.
  final String? savedHost;

  ConnectState copyWith({
    ConnectPhase? phase,
    ConnectSession? session,
    String? failureCause,
    String? savedHost,
  }) => ConnectState(
    phase: phase ?? this.phase,
    session: session ?? this.session,
    failureCause: failureCause,
    savedHost: savedHost ?? this.savedHost,
  );
}

final connectServiceProvider = Provider<ConnectService>((ref) {
  return ConnectService();
});

final targetStoreProvider = FutureProvider<TargetStore>((ref) async {
  return TargetStore(preferences: await SharedPreferences.getInstance());
});

/// Backs the connect form and drives auto-reconnect at app start. Replaces
/// `launcher_bootstrap_notifier.dart` plus the connect half of
/// `deployment_notifier.dart` (see the CEL-25 plan document) — this notifier
/// only ever calls [ConnectService], never SSH.
class ConnectNotifier extends Notifier<ConnectState> {
  @override
  ConnectState build() => const ConnectState();

  /// Called once at app start. Resolves to `connected` fast on a working
  /// saved credential, else `failed` with [ConnectState.savedHost] set so the
  /// connect form can prefill the host that needs re-entering credentials.
  Future<void> reconnectOnOpen() async {
    final store = await ref.read(targetStoreProvider.future);
    final last = await store.loadLastTarget();
    if (last == null ||
        last.sessionToken.isEmpty ||
        last.credential.isEmpty) {
      state = ConnectState(
        phase: ConnectPhase.failed,
        savedHost: last?.host,
        failureCause: last == null
            ? 'No saved server to reconnect to.'
            : 'No saved session for this server. Log in again.',
      );
      return;
    }
    await _authenticate(
      () => ref.read(connectServiceProvider).reconnect(last),
      savedHost: last.host,
    );
  }

  /// Submits the connect form. Retry is calling this again with a re-entered
  /// credential.
  Future<void> connect(ConnectRequest request) {
    return _authenticate(
      () => ref
          .read(connectServiceProvider)
          .login(
            host: request.host,
            username: request.appUsername,
            credential: request.credential,
          ),
      savedHost: request.host,
      credential: request.credential,
    );
  }

  Future<void> _authenticate(
    Future<ConnectSession> Function() attempt, {
    required String savedHost,
    String credential = '',
  }) async {
    state = ConnectState(phase: ConnectPhase.reconnecting, savedHost: savedHost);
    try {
      final session = await attempt();
      final store = await ref.read(targetStoreProvider.future);
      await store.saveTarget(
        ConnectTarget(
          host: session.host,
          appUsername: session.username,
          sessionToken: session.sessionToken,
          credential: credential,
        ),
      );
      state = ConnectState(
        phase: ConnectPhase.connected,
        session: session,
        savedHost: session.host,
      );
    } on ConnectException catch (error) {
      state = ConnectState(
        phase: ConnectPhase.failed,
        failureCause: error.message,
        savedHost: savedHost,
      );
    } on Object catch (error) {
      state = ConnectState(
        phase: ConnectPhase.failed,
        failureCause: error.toString(),
        savedHost: savedHost,
      );
    }
  }

  void logout() {
    state = const ConnectState();
  }
}

final connectNotifierProvider = NotifierProvider<ConnectNotifier, ConnectState>(
  ConnectNotifier.new,
);
