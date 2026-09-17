import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/bootstrap_transcript_parsing.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';

/// Runs the remote bootstrap script over one administrator SSH session and
/// tracks it so [cancel] can kill an in-progress setup on request.
class AdministratorSessionManager {
  final Map<String, _AdministratorOperation> _operations = {};

  Future<SSHRunResult> runScript(
    SSHClient client, {
    required String script,
    required String rootUsername,
    required String rootPassword,
    required String jobId,
    required List<String> redactionSecrets,
    Future<void> Function(DeploymentPhase phase, double percent, String label)?
    onPhase,
    Future<void> Function(DeploymentActiveOperation? operation)? onOperation,
    Future<void> Function(String line)? onTerminalOutput,
  }) async {
    final needsSudo = rootUsername != 'root';
    final session = await client.execute(
      administratorShellCommand(needsSudo: needsSudo),
    );
    _operations[jobId] = _AdministratorOperation(client, session);
    Timer? idleWatchdog;
    try {
      final stdoutLines = <String>[];
      final stderrLines = <String>[];
      final operationTimeout = Completer<DeploymentFailureDetails>();
      final scriptCompleted = Completer<int>();
      var currentPhase = DeploymentPhase.bootstrappingAccess.wireName;
      var streamedUpdates = Future<void>.value();
      DeploymentActiveOperation? activeOperation;
      var activeOperationTimeoutSeconds = 0;

      // Every line the server prints rearms this timer, so no part of the
      // bootstrap is left unguarded. The previous watchdog was armed only
      // between a step's start and finish markers, which left the gaps between
      // steps — and the whole tail after the last step — able to hang forever.
      void armIdleWatchdog() {
        idleWatchdog?.cancel();
        if (scriptCompleted.isCompleted || operationTimeout.isCompleted) return;
        final operation = activeOperation;
        final seconds = operation == null
            ? bootstrapIdleTimeoutSeconds
            : activeOperationTimeoutSeconds + 7;
        idleWatchdog = Timer(Duration(seconds: seconds), () {
          if (operationTimeout.isCompleted || scriptCompleted.isCompleted) {
            return;
          }
          operationTimeout.complete(
            operation == null
                ? administratorStallDetails(phase: currentPhase)
                : administratorStepTimeoutDetails(
                    label: operation.label,
                    timeoutSeconds: activeOperationTimeoutSeconds,
                    phase: currentPhase,
                  ),
          );
          session.kill(SSHSignal.TERM);
          session.close();
          client.close();
        });
      }

      void handleLine(String line, List<String> destination) {
        destination.add(line);
        final doneMarker = RegExp(
          r'^NMTK_SETUP_DONE\|(-?\d+)$',
        ).firstMatch(line);
        if (doneMarker != null) {
          idleWatchdog?.cancel();
          if (!scriptCompleted.isCompleted) {
            scriptCompleted.complete(int.parse(doneMarker.group(1)!));
          }
          return;
        }
        armIdleWatchdog();
        final phaseMarker = RegExp(
          r'^NMTK_SETUP_PHASE\|([^|]+)\|([^|]+)\|(.+)$',
        ).firstMatch(line);
        if (phaseMarker != null && onPhase != null) {
          currentPhase = phaseMarker.group(1) ?? currentPhase;
          final phase = DeploymentPhase.values.firstWhere(
            (candidate) => candidate.wireName == phaseMarker.group(1),
            orElse: () => DeploymentPhase.bootstrappingAccess,
          );
          streamedUpdates = streamedUpdates.then(
            (_) => onPhase(
              phase,
              double.tryParse(phaseMarker.group(2) ?? '') ?? 5,
              phaseMarker.group(3) ?? 'Preparing server',
            ),
          );
          return;
        }
        final operationMarker = bootstrapOperationMarker(line);
        if (operationMarker != null) {
          DeploymentActiveOperation? operation;
          if (operationMarker.state == 'start') {
            operation = DeploymentActiveOperation(
              label: operationMarker.label,
              startedAt: DateTime.now(),
              timeoutSeconds: operationMarker.timeoutSeconds,
              automaticRecovery: operationMarker.automaticRecovery,
            );
            activeOperationTimeoutSeconds = operationMarker.timeoutSeconds;
          }
          activeOperation = operation;
          armIdleWatchdog();
          if (onOperation != null) {
            streamedUpdates = streamedUpdates.then(
              (_) => onOperation(operation),
            );
          }
          return;
        }
        if (onTerminalOutput == null) return;
        final safeLine = bootstrapTranscriptLine(
          line,
          rootPassword: redactionSecrets.elementAtOrNull(0) ?? '',
          rootPrivateKey: redactionSecrets.elementAtOrNull(1) ?? '',
        );
        if (safeLine != null && safeLine.isNotEmpty) {
          streamedUpdates = streamedUpdates.then(
            (_) => onTerminalOutput(safeLine),
          );
        }
      }

      final stdout = session.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => handleLine(line, stdoutLines));
      final stderr = session.stderr
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => handleLine(line, stderrLines));
      final input = needsSudo && rootPassword.isNotEmpty
          ? '$rootPassword\n$script'
          : script;
      session.stdin.add(Uint8List.fromList(utf8.encode(input)));
      await session.stdin.close();
      armIdleWatchdog();
      // The script announcing its own exit is authoritative. Channel EOF is
      // not: sshd holds the channel open until every process that inherited
      // this session's stdout and stderr has exited, and preparing rootless
      // Podman deliberately leaves lingering processes behind.
      final outcome = await Future.any<Object>([
        scriptCompleted.future.then<Object>(_AdministratorSessionExit.new),
        session
            .waitForExit(timeout: const Duration(minutes: 12))
            .then<Object>(_AdministratorSessionExit.new),
        operationTimeout.future,
      ]);
      idleWatchdog?.cancel();
      if (outcome is DeploymentFailureDetails) {
        await Future.wait<void>([stdout.cancel(), stderr.cancel()]);
        await settleStreamedUpdates(streamedUpdates);
        throw RemoteSetupException(outcome);
      }
      final exitCode = (outcome as _AdministratorSessionExit).exitCode;
      if (exitCode == null && session.exitSignal == null) {
        session.kill(SSHSignal.TERM);
        session.close();
        client.close();
        await Future.wait<void>([stdout.cancel(), stderr.cancel()]);
        await settleStreamedUpdates(streamedUpdates);
        throw const RemoteSetupException(
          DeploymentFailureDetails(
            code: 'administrator_session_timeout',
            phase: 'bootstrapping_access',
            summary: 'Administrator setup timed out',
            recovery:
                'Open the terminal output to identify the command that timed out, then retry.',
          ),
        );
      }
      await drainTranscriptStreams(stdout, stderr);
      session.close();
      await settleStreamedUpdates(streamedUpdates);
      final stdoutBytes = utf8.encode(stdoutLines.join('\n'));
      final stderrBytes = utf8.encode(stderrLines.join('\n'));
      return SSHRunResult(
        output: Uint8List.fromList([...stdoutBytes, ...stderrBytes]),
        exitCode: exitCode ?? 1,
        stdout: Uint8List.fromList(stdoutBytes),
        stderr: Uint8List.fromList(stderrBytes),
        exitSignal: session.exitSignal,
      );
    } finally {
      idleWatchdog?.cancel();
      if (identical(_operations[jobId]?.session, session)) {
        _operations.remove(jobId);
      }
    }
  }

  /// Kills the in-progress administrator session for [jobId], if any.
  /// Returns whether one was found and cancelled.
  bool cancel(String jobId) {
    final operation = _operations.remove(jobId);
    if (operation == null) return false;
    operation.session.kill(SSHSignal.TERM);
    operation.session.close();
    operation.client.close();
    return true;
  }
}

class _AdministratorOperation {
  const _AdministratorOperation(this.client, this.session);

  final SSHClient client;
  final SSHSession session;
}

class _AdministratorSessionExit {
  const _AdministratorSessionExit(this.exitCode);

  final int? exitCode;
}

class RemoteSetupException implements Exception {
  const RemoteSetupException(this.details);

  final DeploymentFailureDetails details;

  @override
  String toString() => details.summary;
}
