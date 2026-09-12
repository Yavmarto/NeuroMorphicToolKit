import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/server/connect/connect_build_policy.dart';
import 'package:neuro_toolkit/features/server/connect/connect_service.dart';
import 'package:neuro_toolkit/features/server/shared/target_store.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';

enum ConnectPhase { idle, reconnecting, connected, devOffline, failed }

const _unexpectedConnectFailureMessage =
    'Could not sign in. Check your connection and try again.';

/// What the connect form submits. Release builds require [appUsername] and
/// [credential]; debug/profile builds only use [host] (CEL-220).
class ConnectRequest {
  const ConnectRequest({
    required this.host,
    this.appUsername = '',
    this.credential = '',
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
    this.savedUsername,
  });

  final ConnectPhase phase;
  final ConnectSession? session;
  final String? failureCause;

  /// The last saved target's host, for prefilling the connect form.
  final String? savedHost;

  /// The last saved app username, for prefilling the connect form.
  final String? savedUsername;

  ConnectState copyWith({
    ConnectPhase? phase,
    ConnectSession? session,
    String? failureCause,
    String? savedHost,
    String? savedUsername,
  }) => ConnectState(
    phase: phase ?? this.phase,
    session: session ?? this.session,
    failureCause: failureCause,
    savedHost: savedHost ?? this.savedHost,
    savedUsername: savedUsername ?? this.savedUsername,
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

  /// Called once at app start. Release builds restore a saved credential;
  /// debug/profile builds probe the saved host or [ConnectBuildPolicy.defaultDevServerHost].
  Future<void> reconnectOnOpen() async {
    if (state.phase == ConnectPhase.connected ||
        state.phase == ConnectPhase.devOffline ||
        state.phase == ConnectPhase.reconnecting) {
      return;
    }

    if (!ConnectBuildPolicy.requiresCredentialAuth) {
      final store = await ref.read(targetStoreProvider.future);
      final last = await store.loadLastTarget();
      final host = last?.host ?? ConnectBuildPolicy.defaultDevServerHost;
      await _connectToHost(host);
      return;
    }

    final store = await ref.read(targetStoreProvider.future);
    final last = await store.loadLastTarget();
    if (last == null || last.credential.isEmpty) {
      state = ConnectState(
        phase: ConnectPhase.failed,
        savedHost: last?.host,
        savedUsername: last?.appUsername,
        failureCause: last == null
            ? 'No saved server to reconnect to.'
            : 'No saved credential for this server. Log in again.',
      );
      return;
    }
    await _authenticate(
      () => ref.read(connectServiceProvider).reconnect(last),
      savedHost: last.host,
      credential: last.credential,
    );
  }

  /// Submits the connect form.
  Future<void> connect(ConnectRequest request) {
    if (!ConnectBuildPolicy.requiresCredentialAuth) {
      return _connectToHost(request.host);
    }
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

  /// Debug/profile path: reachability probe only, no credential (CEL-171/220).
  Future<void> _connectToHost(String host) async {
    state = ConnectState(phase: ConnectPhase.reconnecting, savedHost: host);

    try {
      final String normalizedHost;
      try {
        normalizedHost = ControlApiService.normalizeBaseUri(host).host;
      } on FormatException catch (error) {
        state = ConnectState(
          phase: ConnectPhase.failed,
          savedHost: host,
          failureCause: error.message,
        );
        return;
      }

      final reachable = await ref
          .read(connectServiceProvider)
          .probe(host: normalizedHost);
      if (!reachable) {
        state = ConnectState(
          phase: ConnectPhase.failed,
          savedHost: host,
          failureCause:
              'Could not reach $normalizedHost. Confirm the address and that '
              'the server is running, then try again.',
        );
        return;
      }

      final session = ConnectSession(
        host: normalizedHost,
        username: '',
        sessionToken: '',
      );
      state = ConnectState(
        phase: ConnectPhase.connected,
        session: session,
        savedHost: normalizedHost,
      );

      // ponytail: persistence must not block or undo a successful probe — a
      // keychain/prefs write failure still leaves the user connected (CEL-227).
      try {
        final store = await ref.read(targetStoreProvider.future);
        await store.saveTarget(
          ConnectTarget(host: normalizedHost, appUsername: ''),
        );
      } on Object {
        // Connected state already published; next launch may re-probe.
      }
    } on Object {
      state = ConnectState(
        phase: ConnectPhase.failed,
        savedHost: host,
        failureCause: _unexpectedConnectFailureMessage,
      );
    }
  }

  Future<void> _authenticate(
    Future<ConnectSession> Function() attempt, {
    required String savedHost,
    String credential = '',
  }) async {
    state = ConnectState(
      phase: ConnectPhase.reconnecting,
      savedHost: savedHost,
      savedUsername: state.savedUsername,
    );
    try {
      final session = await attempt();
      state = ConnectState(
        phase: ConnectPhase.connected,
        session: session,
        savedHost: session.host,
        savedUsername: session.username,
      );
      try {
        final store = await ref.read(targetStoreProvider.future);
        await store.saveTarget(
          ConnectTarget(
            host: session.host,
            appUsername: session.username,
            sessionToken: session.sessionToken,
            credential: credential,
          ),
        );
      } on Object {
        // Connected state already published; next launch may re-prompt.
      }
    } on ConnectException catch (error) {
      state = ConnectState(
        phase: ConnectPhase.failed,
        failureCause: error.message,
        savedHost: savedHost,
        savedUsername: state.savedUsername,
      );
    } on Object {
      state = ConnectState(
        phase: ConnectPhase.failed,
        failureCause: _unexpectedConnectFailureMessage,
        savedHost: savedHost,
        savedUsername: state.savedUsername,
      );
    }
  }

  void logout() {
    state = const ConnectState();
  }

  /// Bypasses server sign-in to allow exploring/navigating the app in dev mode.
  void continueWithoutServer() {
    state = const ConnectState(phase: ConnectPhase.devOffline);
  }
}

final connectNotifierProvider = NotifierProvider<ConnectNotifier, ConnectState>(
  ConnectNotifier.new,
);

/// Monotonic counter the workspace bumps to ask the connection gate to reopen
/// its sign-in/setup popup. The gate compares consecutive values, so an
/// explicit reopen request is observable even when `ConnectState` itself does
/// not change (e.g. already logged out and just re-showing the form).
class ServerAccessPopupRequestNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

final serverAccessPopupRequestProvider =
    NotifierProvider<ServerAccessPopupRequestNotifier, int>(
      ServerAccessPopupRequestNotifier.new,
    );
