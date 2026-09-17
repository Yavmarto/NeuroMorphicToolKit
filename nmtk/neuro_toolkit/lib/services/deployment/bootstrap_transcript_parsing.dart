import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';

/// Grace period for a transcript stream pair to reach EOF once its remote
/// command/script has reported its own exit. See [drainTranscriptStreams].
const administratorDrainTimeout = Duration(seconds: 3);

/// Grace period for queued progress persistence once a remote session is over.
const streamedUpdateSettleTimeout = Duration(seconds: 10);

/// Waits for the transcript streams to close, but never longer than
/// [timeout].
///
/// A held-open channel is expected here rather than exceptional: the
/// deployment account's rootless Podman service and its pause processes
/// inherit the session's descriptors and outlive the remote command on
/// purpose. Both streams have already delivered every line that was printed,
/// so nothing is lost by giving up on EOF.
Future<void> drainTranscriptStreams(
  StreamSubscription<String> stdout,
  StreamSubscription<String> stderr, {
  Duration timeout = administratorDrainTimeout,
}) async {
  try {
    await Future.wait<void>([
      stdout.asFuture<void>(),
      stderr.asFuture<void>(),
    ]).timeout(timeout);
  } on TimeoutException {
    // Expected when a lingering server process still holds the channel.
  } on Object {
    // The exit status already decided the outcome; a late channel error
    // cannot invalidate output that was delivered line by line.
  } finally {
    await Future.wait<void>([stdout.cancel(), stderr.cancel()]);
  }
}

@visibleForTesting
Future<void> drainTranscriptStreamsForTesting(
  StreamSubscription<String> stdout,
  StreamSubscription<String> stderr, {
  Duration timeout = administratorDrainTimeout,
}) => drainTranscriptStreams(stdout, stderr, timeout: timeout);

/// Lets the queued progress callbacks finish without letting a wedged write
/// block the deployment. Errors still propagate.
Future<void> settleStreamedUpdates(
  Future<void> streamedUpdates, {
  Duration timeout = streamedUpdateSettleTimeout,
}) => streamedUpdates.timeout(timeout, onTimeout: () {});

@visibleForTesting
Future<void> settleStreamedUpdatesForTesting(
  Future<void> streamedUpdates, {
  Duration timeout = streamedUpdateSettleTimeout,
}) => settleStreamedUpdates(streamedUpdates, timeout: timeout);

/// How long the administrator session may stay silent while no single server
/// command is nominally running. Long enough to cover the gaps between steps,
/// short enough that a wedged bootstrap surfaces while the user is still
/// watching.
const bootstrapIdleTimeoutSeconds = 90;

DeploymentFailureDetails bootstrapFailureDetails(
  String stderr, {
  required int exitCode,
  required String rootPassword,
  required String rootPrivateKey,
}) {
  final sanitized = boundedDiagnosticOutput(
    redactBootstrapOutput(stderr, rootPassword, rootPrivateKey),
  );
  final marker = RegExp(
    r'NMTK_SETUP_ERROR\|([^|]+)\|([^|]+)\|(\d+)\|([^\r\n]+)',
  ).allMatches(stderr).lastOrNull;
  final code = marker?.group(1) ?? legacyBootstrapCode(stderr);
  final phase = marker?.group(2) ?? phaseForFailureCode(code);
  final details = failureCopyForCode(code);
  // When the server names the account it stumbled on, that sentence is the
  // only place the name appears — the code's stock copy cannot know it, and
  // the ✓/✗ lines that used to carry it never reach the transcript. The
  // generic "… failed or timed out." wording adds nothing, so skip it.
  final serverMessage = marker?.group(4)?.trim() ?? '';
  final recovery =
      serverMessage.contains(' user ') &&
          !serverMessage.endsWith('failed or timed out.')
      ? '$serverMessage ${details.$2}'
      : details.$2;
  return DeploymentFailureDetails(
    code: code,
    phase: phase,
    summary: details.$1,
    recovery: recovery,
    technicalDetails: sanitized,
    exitCode: int.tryParse(marker?.group(3) ?? '') ?? exitCode,
  );
}

@visibleForTesting
DeploymentFailureDetails parseBootstrapFailureForTesting(
  String stderr, {
  required int exitCode,
  String rootPassword = '',
  String rootPrivateKey = '',
}) {
  return bootstrapFailureDetails(
    stderr,
    exitCode: exitCode,
    rootPassword: rootPassword,
    rootPrivateKey: rootPrivateKey,
  );
}

String legacyBootstrapCode(String stderr) {
  final lower = stderr.toLowerCase();
  if (lower.contains('sudo') &&
      (lower.contains('password') ||
          lower.contains('authentication') ||
          lower.contains('privileged'))) {
    return 'sudo_access_denied';
  }
  if (lower.contains('unsupported operating system')) {
    return 'unsupported_os';
  }
  if (lower.contains('disk space')) return 'insufficient_disk';
  if (lower.contains('installed but inaccessible')) {
    return lower.contains('podman')
        ? 'podman_inspection_failed'
        : 'docker_inspection_failed';
  }
  if (lower.contains('cleanup failed')) return 'container_cleanup_failed';
  return 'unknown_bootstrap_failure';
}

String phaseForFailureCode(String code) {
  if (code.contains('cleanup') || code.contains('inspection')) {
    return DeploymentPhase.reconcilingExistingInstall.wireName;
  }
  if (code.contains('install') || code == 'unsupported_os') {
    return DeploymentPhase.installingPrerequisites.wireName;
  }
  if (code == 'insufficient_disk') {
    return DeploymentPhase.preflight.wireName;
  }
  return DeploymentPhase.bootstrappingAccess.wireName;
}

(String, String) failureCopyForCode(String code) {
  return switch (code) {
    'sudo_access_denied' => (
      'Administrator privileges could not be confirmed',
      'Use an account that can run sudo, check its password, then retry.',
    ),
    'unsupported_os' => (
      'This server operating system is not supported',
      'Remote setup requires a Debian or Ubuntu Linux server.',
    ),
    'insufficient_disk' => (
      'The server does not have enough free disk space',
      'Free at least 5 GB on the server, then retry.',
    ),
    'docker_inspection_failed' => (
      'Docker installations could not be inspected',
      'Ensure Docker is running and the administrator can access it, then retry.',
    ),
    'podman_inspection_failed' => (
      'Podman installations could not be inspected',
      'Administrator access succeeded, but the server’s own Podman '
          'installation did not answer. Restart the server, then retry. '
          'Podman belonging to other accounts on the server is skipped '
          'automatically and never blocks setup.',
    ),
    'container_cleanup_failed' => (
      'Existing NMTK containers could not be removed safely',
      'Review the administrator details, correct the reported container permission, then retry.',
    ),
    'volume_cleanup_failed' => (
      'NMTK server data could not be erased safely',
      'Review the volume permission shown in the details before retrying Factory Reset.',
    ),
    'engine_install_failed' => (
      'The selected container engine could not be installed',
      'Check package-manager and network access on the server, then retry.',
    ),
    'deploy_account_failed' => (
      'The deployment account could not be prepared',
      'The app could not repair the server’s deployment account '
          'automatically. Restart the server, then select Retry setup.',
    ),
    'podman_api_start_failed' => (
      'The Podman service could not be started',
      'The app tried both supported Podman startup methods automatically. '
          'Restart the server, then select Set up and connect again.',
    ),
    _ => (
      'The server preparation command failed',
      'Open the administrator details below, correct the reported server error, then retry.',
    ),
  };
}

String redactBootstrapOutput(
  String value,
  String rootPassword,
  String rootPrivateKey,
) {
  var result = value;
  for (final secret in [rootPassword, rootPrivateKey]) {
    if (secret.isNotEmpty) result = result.replaceAll(secret, '[redacted]');
  }
  result = result.replaceAll(
    RegExp(r'NMTK_DEPLOY_PRIVATE_KEY_B64=[A-Za-z0-9+/=]+'),
    'NMTK_DEPLOY_PRIVATE_KEY_B64=[redacted]',
  );
  result = result.replaceAll(
    RegExp(
      r'-----BEGIN OPENSSH PRIVATE KEY-----[\s\S]*?-----END OPENSSH PRIVATE KEY-----',
    ),
    '[redacted private key]',
  );
  result = result.replaceAllMapped(
    RegExp(
      r'\b(password|token|api[_-]?key|secret)=([^\s]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=[redacted]',
  );
  result = result.replaceAllMapped(
    RegExp(
      r'\b(NMTK_[A-Z0-9_]*(?:PASSWORD|TOKEN|PRIVATE_KEY|SECRET))=([^\s]+)',
    ),
    (match) => '${match.group(1)}=[redacted]',
  );
  result = result.replaceAllMapped(
    RegExp(
      r'(authorization:\s*(?:bearer|basic)\s+)([^\s]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}[redacted]',
  );
  result = result.replaceAllMapped(
    RegExp(
      r'([a-z][a-z0-9+.-]*://)([^/\s:@]+):([^@\s/]+)@',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}[redacted]@',
  );
  result = result
      .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
  return result;
}

String boundedDiagnosticOutput(String value) {
  const maxCharacters = 8000;
  final normalized = value.trim();
  if (normalized.length <= maxCharacters) return normalized;
  return '… output truncated …\n'
      '${normalized.substring(normalized.length - maxCharacters)}';
}

List<String> replaceRemoteInstallOutput(
  List<String> existing,
  List<String> remoteLines,
) {
  const marker = '[client: remote install output]';
  final markerIndex = existing.indexOf(marker);
  final bootstrapAndCommands = markerIndex == -1
      ? List<String>.of(existing)
      : existing.sublist(0, markerIndex);
  if (remoteLines.isEmpty) {
    return boundedTerminalOutput(bootstrapAndCommands);
  }
  return boundedTerminalOutput([
    ...bootstrapAndCommands,
    marker,
    ...remoteLines,
  ]);
}

String? bootstrapTranscriptLine(
  String line, {
  required String rootPassword,
  required String rootPrivateKey,
}) {
  if (line.startsWith('NMTK_SETUP_PHASE|') ||
      line.startsWith('NMTK_SETUP_STEP|') ||
      line.startsWith('NMTK_SETUP_DONE|') ||
      line.startsWith('NMTK_SETUP_ERROR|') ||
      line.startsWith('NMTK_SETUP_TERMINAL|') ||
      line.startsWith('NMTK_DEPLOY_PRIVATE_KEY_B64=')) {
    return null;
  }
  final commandMarker = RegExp(r'^NMTK_SETUP_COMMAND\|(.*)$').firstMatch(line);
  final commandExitMarker = RegExp(
    r'^NMTK_SETUP_COMMAND_EXIT\|([^|]+)\|(.+)$',
  ).firstMatch(line);
  final transcriptLine = commandMarker != null
      ? '\$ ${commandMarker.group(1) ?? ''}'
      : commandExitMarker?.group(1) == 'timeout'
      ? '[client: command timed out after '
            '${commandExitMarker?.group(2)}s]'
      : commandExitMarker != null
      ? '[client: command exited ${commandExitMarker.group(2)}]'
      : line;
  return redactBootstrapOutput(transcriptLine, rootPassword, rootPrivateKey);
}

({String state, int timeoutSeconds, bool automaticRecovery, String label})?
bootstrapOperationMarker(String line) {
  final marker = RegExp(
    r'^NMTK_SETUP_STEP\|(start|finish)\|(\d+)\|(true|false)\|([^|\r\n]+)$',
  ).firstMatch(line);
  final timeoutSeconds = int.tryParse(marker?.group(2) ?? '');
  if (marker == null || timeoutSeconds == null || timeoutSeconds <= 0) {
    return null;
  }
  return (
    state: marker.group(1)!,
    timeoutSeconds: timeoutSeconds,
    automaticRecovery: marker.group(3) == 'true',
    label: marker.group(4)!,
  );
}

@visibleForTesting
({String state, int timeoutSeconds, bool automaticRecovery, String label})?
parseBootstrapOperationMarkerForTesting(String line) {
  return bootstrapOperationMarker(line);
}

DeploymentFailureDetails administratorStepTimeoutDetails({
  required String label,
  required int timeoutSeconds,
  required String phase,
}) {
  return DeploymentFailureDetails(
    code: 'administrator_step_timeout',
    phase: phase,
    summary: '$label timed out',
    recovery:
        'The app stopped this server step automatically. '
        'Select Retry; if it times out again, open the raw SSH output to '
        'identify the server problem.',
    technicalDetails:
        '$label did not finish within its '
        '$timeoutSeconds-second command timeout and cleanup grace.',
    exitCode: 124,
  );
}

/// Reported when the server stops printing anything while no single command
/// is nominally responsible — the gap that used to leave setup at the same
/// percentage indefinitely.
DeploymentFailureDetails administratorStallDetails({required String phase}) {
  return DeploymentFailureDetails(
    code: 'administrator_stalled',
    phase: phase,
    summary: 'The server stopped reporting progress',
    recovery:
        'The app stopped waiting automatically. Select Retry; if it '
        'stalls again, open the raw SSH output to see the last command the '
        'server ran.',
    technicalDetails:
        'No server output arrived for '
        '$bootstrapIdleTimeoutSeconds seconds while no command was active.',
    exitCode: 124,
  );
}

@visibleForTesting
DeploymentFailureDetails administratorStallForTesting({required String phase}) {
  return administratorStallDetails(phase: phase);
}

@visibleForTesting
DeploymentFailureDetails administratorStepTimeoutForTesting({
  required String label,
  required int timeoutSeconds,
  required String phase,
}) {
  return administratorStepTimeoutDetails(
    label: label,
    timeoutSeconds: timeoutSeconds,
    phase: phase,
  );
}

@visibleForTesting
String? parseBootstrapTranscriptLineForTesting(
  String line, {
  String rootPassword = '',
  String rootPrivateKey = '',
}) => bootstrapTranscriptLine(
  line,
  rootPassword: rootPassword,
  rootPrivateKey: rootPrivateKey,
);

@visibleForTesting
List<String> boundTerminalOutputForTesting(List<String> lines) =>
    boundedTerminalOutput(lines);

@visibleForTesting
List<String> replaceRemoteInstallOutputForTesting(
  List<String> existing,
  List<String> remoteLines,
) => replaceRemoteInstallOutput(existing, remoteLines);

List<String> boundedTerminalOutput(List<String> lines) {
  const maxLines = 2000;
  const maxCharacters = 512000;
  const truncationMarker = '[client: earlier SSH output truncated]';
  final alreadyTruncated = lines.contains(truncationMarker);
  final source = lines.where((line) => line != truncationMarker).toList();
  var truncated = alreadyTruncated || source.length > maxLines;
  final bounded = source.length > maxLines
      ? source.sublist(source.length - maxLines)
      : List<String>.of(source);
  var characters = bounded.fold<int>(
    0,
    (total, line) => total + line.length + 1,
  );
  while (bounded.isNotEmpty && characters > maxCharacters) {
    characters -= bounded.removeAt(0).length + 1;
    truncated = true;
  }
  if (truncated) {
    while (bounded.length >= maxLines) {
      bounded.removeAt(0);
    }
    while (bounded.isNotEmpty &&
        characters + truncationMarker.length + 1 > maxCharacters) {
      characters -= bounded.removeAt(0).length + 1;
    }
    bounded.insert(0, truncationMarker);
  }
  return List<String>.unmodifiable(bounded);
}

String friendlySshError(Object error) {
  final message = error.toString();
  final lower = message.toLowerCase();
  // Storing/reading the trusted fingerprint for this host failed on this
  // device (e.g. secure storage/keychain access) — unrelated to whether
  // the credentials are correct, so don't call it an auth failure.
  if (lower.contains('host key trust check failed')) {
    return 'Could not save or verify this server\'s trusted host key on '
        'this device: $message. This is unrelated to the administrator '
        'password or key.';
  }
  if (lower.contains('hostkey verification failed') ||
      lower.contains('signature verification failed')) {
    return 'The SSH host key does not match the one previously trusted '
        'for this server. Confirm the server\'s identity before retrying.';
  }
  // The transport closed before any credential was checked — e.g.
  // fail2ban/rate limiting, MaxStartups throttling, or a firewall reset.
  // Distinct from a real credential rejection, which arrives as a
  // userauth failure message instead of the connection dropping early.
  if (lower.contains('closed before authentication')) {
    return 'The server closed the connection before authentication could '
        'happen. This usually means the server is rate-limiting or '
        'blocking this connection (e.g. fail2ban, MaxStartups) rather than '
        'rejecting the credentials. Check the server\'s SSH/auth logs, '
        'wait a bit, then retry.';
  }
  if (lower.contains('auth')) {
    return 'SSH authentication failed. Check the username and credentials.';
  }
  return 'Could not connect over SSH: $message';
}

String redactForLogging(String value, DeploymentRequest request) {
  var result = value;
  for (final secret in [
    request.sshPassword,
    request.sshPrivateKey,
    request.kubeconfig,
  ]) {
    if (secret.isNotEmpty) result = result.replaceAll(secret, '[redacted]');
  }
  return redactBootstrapOutput(result, '', '');
}

String shellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

String administratorShellCommand({required bool needsSudo}) =>
    needsSudo ? 'sudo -S -p "" bash' : 'bash';
