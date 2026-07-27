import 'package:dartssh2/dartssh2.dart';
import 'package:neuro_toolkit/services/deployment/deployment_persistence.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';

/// Owns SSH transport and authentication for client-side deployments.
class SshDeploymentService {
  const SshDeploymentService();

  Future<SSHClient> connect({
    required DeploymentRequest request,
    required DeploymentPersistence persistence,
  }) async {
    final socket = await SSHSocket.connect(
      request.host,
      request.sshPort,
      timeout: const Duration(seconds: 15),
    );
    final client = SSHClient(
      socket,
      username: request.username,
      identities: request.authMethod == 'ssh_key' &&
              request.sshPrivateKey.trim().isNotEmpty
          ? SSHKeyPair.fromPem(request.sshPrivateKey)
          : null,
      onPasswordRequest: request.authMethod == 'ssh_password'
          ? () => request.sshPassword
          : null,
      onVerifyHostKey: (_, fingerprint) => persistence.verifyOrTrustHostKey(
        host: request.host,
        port: request.sshPort,
        fingerprint: fingerprint,
      ),
      handshakeTimeout: const Duration(seconds: 15),
      authTimeout: const Duration(seconds: 15),
      ident: 'NeuroToolkit',
    );
    try {
      await client.authenticated;
      return client;
    } catch (_) {
      client.close();
      rethrow;
    }
  }
}
