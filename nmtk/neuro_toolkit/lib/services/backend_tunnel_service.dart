import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/deployment_persistence.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/ssh_deployment_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackendTunnelSession {
  const BackendTunnelSession({
    required this.launcherUri,
    required this.suiteApiUri,
    required this.jupyterUri,
    required this.adminToken,
  });

  final Uri launcherUri;
  final Uri suiteApiUri;
  final Uri jupyterUri;
  final String adminToken;
}

/// Owns session-only loopback listeners backed by the selected SSH target.
class BackendTunnelService {
  BackendTunnelService({
    SshDeploymentService ssh = const SshDeploymentService(),
  }) : _ssh = ssh;

  final SshDeploymentService _ssh;
  final List<ServerSocket> _listeners = [];
  final List<StreamSubscription<Socket>> _subscriptions = [];
  final Set<Socket> _sockets = {};
  final Set<SSHForwardChannel> _channels = {};
  SSHClient? _client;
  DeploymentRequest? _request;
  DeploymentPersistence? _persistence;
  Future<SSHClient>? _connecting;
  BackendTunnelSession? currentSession;

  Future<BackendTunnelSession> open(DeploymentTarget target) async {
    await close();
    final persistence = DeploymentPersistence(
      preferences: await SharedPreferences.getInstance(),
    );
    final request = await persistence.requestForTarget(target);
    if (request.adminToken.isEmpty) {
      throw StateError(
        'This app could not read the running backend\'s administrator '
        'credential, so it cannot open a secure tunnel to it. Reinstall and '
        'keep data to issue a new one.',
      );
    }
    _request = request;
    _persistence = persistence;
    await _ensureClient();
    final launcher = await _listen(8090);
    final suiteApi = await _listen(9000);
    final jupyter = await _listen(8008);
    return currentSession = BackendTunnelSession(
      launcherUri: Uri.parse('http://127.0.0.1:${launcher.port}'),
      suiteApiUri: Uri.parse('http://127.0.0.1:${suiteApi.port}'),
      jupyterUri: Uri.parse('http://127.0.0.1:${jupyter.port}'),
      adminToken: request.adminToken,
    );
  }

  Future<ServerSocket> _listen(int remotePort) async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _listeners.add(listener);
    _subscriptions.add(
      listener.listen((socket) {
        unawaited(_forward(socket, remotePort));
      }),
    );
    return listener;
  }

  Future<void> _forward(Socket socket, int remotePort) async {
    SSHForwardChannel? channel;
    _sockets.add(socket);
    try {
      channel = await (await _ensureClient()).forwardLocal(
        '127.0.0.1',
        remotePort,
      );
      _channels.add(channel);
      unawaited(socket.cast<List<int>>().pipe(channel.sink));
      await channel.stream.cast<List<int>>().pipe(socket);
    } on Object {
      socket.destroy();
      channel?.destroy();
      _client?.close();
      _client = null;
    } finally {
      _sockets.remove(socket);
      if (channel != null) _channels.remove(channel);
    }
  }

  Future<SSHClient> _ensureClient() async {
    final active = _client;
    if (active != null) return active;
    final pending = _connecting;
    if (pending != null) return pending;
    final request = _request;
    final persistence = _persistence;
    if (request == null || persistence == null) {
      throw StateError('No backend deployment target is selected.');
    }
    final connecting = _connectWithBackoff(request, persistence);
    _connecting = connecting;
    try {
      return _client = await connecting;
    } finally {
      _connecting = null;
    }
  }

  Future<SSHClient> _connectWithBackoff(
    DeploymentRequest request,
    DeploymentPersistence persistence,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt += 1) {
      try {
        return await _ssh.connect(request: request, persistence: persistence);
      } on Object catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 250 << attempt));
        }
      }
    }
    throw StateError(
      'Could not establish the secure backend tunnel: $lastError',
    );
  }

  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    for (final listener in _listeners) {
      await listener.close();
    }
    _listeners.clear();
    for (final socket in _sockets.toList(growable: false)) {
      socket.destroy();
    }
    _sockets.clear();
    for (final channel in _channels.toList(growable: false)) {
      channel.destroy();
    }
    _channels.clear();
    _client?.close();
    _client = null;
    _request = null;
    _persistence = null;
    currentSession = null;
  }
}
