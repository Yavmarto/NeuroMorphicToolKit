import 'dart:async';
import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/services/admin_token_http_client.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/feature_launch_provider.dart';

part 'server_config_provider.g.dart';

/// Connection status for the backend health check.
enum ConnectionStatus { unknown, checking, connected, failed }

/// Immutable state for the root-selected backend readiness probe.
class ServerConfigState {
  final Uri backendUri;
  final ConnectionStatus status;
  final String? statusMessage;
  final Map<String, dynamic>? healthData;

  ServerConfigState({
    Uri? backendUri,
    @Deprecated('The root launch context owns the backend URI.')
    String? serverUrl,
    this.status = ConnectionStatus.unknown,
    this.statusMessage,
    this.healthData,
  }) : backendUri =
           backendUri ?? Uri.parse(serverUrl ?? 'http://invalid-root-context');

  bool get isConnected => status == ConnectionStatus.connected;

  ServerConfigState copyWith({
    Uri? backendUri,
    ConnectionStatus? status,
    String? statusMessage,
    Map<String, dynamic>? healthData,
    bool clearHealthData = false,
    bool clearStatusMessage = false,
  }) {
    return ServerConfigState(
      backendUri: backendUri ?? this.backendUri,
      status: status ?? this.status,
      statusMessage: clearStatusMessage
          ? null
          : (statusMessage ?? this.statusMessage),
      healthData: clearHealthData ? null : (healthData ?? this.healthData),
    );
  }

  String get serverUrl => backendUri.toString();
}

/// Manages readiness for the connection selected by the root launcher.
@Riverpod(keepAlive: true)
class ServerConfigController extends _$ServerConfigController {
  static const int _httpOk = 200;
  static const int _httpServiceUnavailable = 503;

  @override
  ServerConfigState build() {
    final launchContext = ref.watch(featureLaunchContextProvider);
    return ServerConfigState(backendUri: launchContext.backendUri);
  }

  /// Reset connection feedback after the draft address changes.
  void resetConnectionState() {
    if (state.status == ConnectionStatus.unknown &&
        state.statusMessage == null &&
        state.healthData == null) {
      return;
    }
    state = state.copyWith(
      status: ConnectionStatus.unknown,
      clearHealthData: true,
      clearStatusMessage: true,
    );
  }

  /// Hit `/health` for the root-selected backend and update local readiness.
  Future<void> checkConnection() async {
    final launchContext = ref.read(featureLaunchContextProvider);
    state = state.copyWith(
      backendUri: launchContext.backendUri,
      status: ConnectionStatus.checking,
      statusMessage: 'Checking connection…',
      clearHealthData: true,
    );

    try {
      final uri = launchContext.backendUri.replace(
        path: '${launchContext.backendUri.path}/health',
      );
      final client = AdminTokenHttpClient(
        adminToken: launchContext.authentication.adminToken,
        onReportError: launchContext.onReportError,
        onRecovered: launchContext.onRecovered,
      );
      ref.onDispose(client.close);
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 5));

      if (isReachableHealthStatus(response.statusCode)) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final degraded = response.statusCode == _httpServiceUnavailable;
        state = state.copyWith(
          status: ConnectionStatus.connected,
          statusMessage: degraded
              ? 'Connected to neurocnl backend (degraded optional capability)'
              : 'Connected to neurocnl backend',
          healthData: data,
        );
      } else {
        state = state.copyWith(
          status: ConnectionStatus.failed,
          statusMessage: 'Server returned HTTP ${response.statusCode}',
        );
      }
    } on TimeoutException {
      state = state.copyWith(
        status: ConnectionStatus.failed,
        statusMessage: 'Connection timed out after 5 seconds',
      );
    } catch (e) {
      state = state.copyWith(
        status: ConnectionStatus.failed,
        statusMessage: _friendlyError(e),
      );
    }
  }

  /// Reachable health responses include fully healthy services (200) and
  /// degraded services (503) that still returned a structured health payload.
  static bool isReachableHealthStatus(int statusCode) {
    return statusCode == _httpOk || statusCode == _httpServiceUnavailable;
  }

  static String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('Connection refused')) {
      return 'Cannot reach server — is it running?';
    }
    if (msg.contains('HandshakeException')) {
      return 'TLS/SSL error — check http:// vs https://';
    }
    return 'Connection failed: ${msg.split('\n').first}';
  }
}

/// Backward-compat alias.
final serverConfigProvider = serverConfigControllerProvider;
