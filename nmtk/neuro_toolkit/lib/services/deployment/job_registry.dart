import 'dart:async';

import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/bootstrap_transcript_parsing.dart';
import 'package:neuro_toolkit/services/deployment/deployment_persistence.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';

typedef DeploymentPersistenceFactory = Future<DeploymentPersistence> Function();

/// Owns the in-flight job/target/request state and job-progress glue shared
/// by [ClientDeploymentService] and the collaborators it dispatches to.
///
/// Every deployment collaborator that needs to read or update a job's
/// progress is handed the same [JobRegistry] instance per call, rather than
/// holding its own copy, so a job update from any collaborator is visible to
/// every other one immediately.
class JobRegistry {
  JobRegistry({required DeploymentPersistenceFactory persistenceFactory})
    : _persistenceFactory = persistenceFactory;

  final DeploymentPersistenceFactory _persistenceFactory;
  final Map<String, DeploymentJob> jobs = {};
  final Map<String, Future<void>> runningJobs = {};
  final Map<String, DeploymentTarget> pendingTargets = {};
  final Map<String, DeploymentRequest> pendingRequests = {};
  final Map<String, Timer> _operationHeartbeatTimers = {};
  final Map<String, Timer> _terminalPersistenceTimers = {};
  DeploymentPersistence? _persistence;

  Future<DeploymentPersistence> get store async =>
      _persistence ??= await _persistenceFactory();

  Future<DeploymentJob> updateJob(DeploymentJob job) async {
    if (job.isTerminal) {
      _operationHeartbeatTimers.remove(job.id)?.cancel();
      if (job.activeOperation != null) {
        job = job.copyWith(clearActiveOperation: true);
      }
    }
    _terminalPersistenceTimers.remove(job.id)?.cancel();
    jobs[job.id] = job;
    await (await store).saveActiveJob(job);
    return job;
  }

  Future<void> persistCurrentJob(String jobId) async {
    final current = jobs[jobId];
    if (current != null) {
      await (await store).saveActiveJob(current);
    }
  }

  Future<void> emit(
    DeploymentJob original,
    DeploymentPhase phase,
    double percent,
    String label,
  ) async {
    final current = jobs[original.id] ?? original;
    if (current.stage == DeploymentPhase.cancelled.wireName) return;
    await updateJob(
      current.copyWith(
        stage: phase.wireName,
        percent: percent,
        stageLabel: label,
        logs: [...current.logs, label],
        updatedAt: DateTime.now(),
        lastProgressAt: DateTime.now(),
      ),
    );
  }

  Future<void> setActiveOperation(
    String jobId,
    DeploymentActiveOperation? operation,
  ) async {
    _operationHeartbeatTimers.remove(jobId)?.cancel();
    final current = jobs[jobId];
    if (current == null ||
        current.stage == DeploymentPhase.cancelled.wireName) {
      return;
    }
    await updateJob(
      current.copyWith(
        activeOperation: operation,
        clearActiveOperation: operation == null,
        updatedAt: DateTime.now(),
        lastProgressAt: DateTime.now(),
      ),
    );
    if (operation == null) return;
    _operationHeartbeatTimers[jobId] = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        final latest = jobs[jobId];
        if (latest == null ||
            latest.isTerminal ||
            latest.activeOperation?.startedAt != operation.startedAt) {
          _operationHeartbeatTimers.remove(jobId)?.cancel();
          return;
        }
        unawaited(updateJob(latest.copyWith(updatedAt: DateTime.now())));
      },
    );
  }

  Future<void> appendTerminalOutput(String jobId, String line) async {
    final current = jobs[jobId];
    if (current == null ||
        current.stage == DeploymentPhase.cancelled.wireName) {
      return;
    }
    jobs[jobId] = current.copyWith(
      terminalOutput: boundedTerminalOutput([
        ...current.terminalOutput,
        redactBootstrapOutput(line, '', ''),
      ]),
      updatedAt: DateTime.now(),
      lastProgressAt: DateTime.now(),
    );
    _terminalPersistenceTimers[jobId] ??= Timer(
      const Duration(milliseconds: 300),
      () {
        _terminalPersistenceTimers.remove(jobId);
        unawaited(persistCurrentJob(jobId));
      },
    );
  }
}
