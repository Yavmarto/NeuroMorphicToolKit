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
      // Many servers advertise keyboard-interactive instead of (or alongside)
      // plain password auth (PAM-based sshd configs, hardened cloud images).
      // A manual `ssh` client falls back to it automatically; without this
      // handler dartssh2 never offers the method and auth fails even with
      // correct credentials.
      onUserInfoRequest: request.authMethod == 'ssh_password'
          ? (info) => List.filled(
                info.prompts.isEmpty ? 1 : info.prompts.length,
                request.sshPassword,
              )
          : null,
      onVerifyHostKey: (_, fingerprint) async {
        try {
          return await persistence.verifyOrTrustHostKey(
            host: request.host,
            port: request.sshPort,
            fingerprint: fingerprint,
          );
        } catch (error) {
          throw SSHHostkeyError('Host key trust check failed: $error');
        }
      },
      handshakeTimeout: const Duration(seconds: 15),
      authTimeout: const Duration(seconds: 15),
      ident: 'NeuroToolkit',
    );
    try {
      await client.authenticated;
      return client;
    } catch (authError) {
      // `client.authenticated` always fails with the same generic
      // SSHAuthAbortError('Connection closed before authentication') when the
      // transport closes early (host key rejected, onVerifyHostKey threw,
      // network reset) — dartssh2 discards the real cause on that path
      // (see SSHClient._handleTransportClosed). The real error is only ever
      // preserved on `client.done`, which the client's own internal
      // catchError hook has already populated by the time our await resumes
      // (it was registered before this call and runs first), so prefer it
      // when present.
      var error = authError;
      try {
        await client.done;
      } catch (doneError) {
        error = doneError;
      }
      client.close();
      throw error;
    }
  }
}
