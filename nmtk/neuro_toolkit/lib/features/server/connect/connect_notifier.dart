import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/server/connect/connect_service.dart';
import 'package:neuro_toolkit/features/server/shared/target_store.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';

enum ConnectPhase { idle, reconnecting, connected, devOffline, failed }

/// What the connect form submits: just a server address. Connecting to an
/// already-running dev server never requires a credential -- only
/// `server_setup_screen.dart`'s provisioning flow (SSH/admin, for a
/// brand-new server) still does. See CEL-171.
class ConnectRequest {
  const ConnectRequest({required this.host});

  final String host;
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

/// Backs the connect form and drives auto-reconnect at app start. A device
/// connecting to an already-running server only ever needs the server to
/// answer -- [ConnectService.login] and [ConnectService.reconnect] (the
/// credentialed calls) are deliberately unused here; they remain for
/// server_setup_screen.dart's separate provisioning flow. See CEL-171.
class ConnectNotifier extends Notifier<ConnectState> {
  @override
  ConnectState build() => const ConnectState();

  /// Called once at app start. Resolves to `connected` fast when the saved
  /// host still answers, else `failed` with [ConnectState.savedHost] set so
  /// the connect form can prefill the host that needs retrying.
  Future<void> reconnectOnOpen() async {
    if (state.phase == ConnectPhase.connected ||
        state.phase == ConnectPhase.devOffline) {
      return;
    }
    final store = await ref.read(targetStoreProvider.future);
    final last = await store.loadLastTarget();
    if (last == null) {
      state = const ConnectState(
        phase: ConnectPhase.failed,
        failureCause: 'No saved server to reconnect to.',
      );
      return;
    }
    await _connectToHost(last.host);
  }

  /// Submits the connect form. Retry is calling this again, typically after
  /// the user fixes a typo'd address.
  Future<void> connect(ConnectRequest request) => _connectToHost(request.host);

  Future<void> _connectToHost(String host) async {
    state = ConnectState(phase: ConnectPhase.reconnecting, savedHost: host);

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

    final store = await ref.read(targetStoreProvider.future);
    await store.saveTarget(
      ConnectTarget(host: normalizedHost, appUsername: ''),
    );
    state = ConnectState(
      phase: ConnectPhase.connected,
      session: ConnectSession(
        host: normalizedHost,
        username: '',
        sessionToken: '',
      ),
      savedHost: normalizedHost,
    );
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
