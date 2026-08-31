import 'dart:async';

import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/src/features/deployment/domain/deployment_state.dart';
import 'package:neuro_toolkit/screens/backend_setup/backend_setup_controller_host.dart';
import 'package:neuro_toolkit/screens/backend_setup/form_primitives.dart';

/// Owns the system-health/doctor recovery flow: check → repair →
/// reinstall-keeping-data → factory-reset, a staged escalation
/// (`healthRecoveryStage` 0/1/2) driven both by direct button presses and by
/// the deployment provider's state changes (see [handleDeploymentStateChanged]).
class SystemHealthController {
  SystemHealthController(this._host) {
    resetConfirmation.addListener(_onResetConfirmationChanged);
  }

  final BackendSetupControllerHost _host;

  SystemHealthReport? systemHealth;
  bool healthCheckRunning = false;
  bool healthRepairRunning = false;
  bool healthCheckedAutomatically = false;
  int healthRecoveryStage = 0;
  bool preserveDataReinstallRequested = false;
  String? systemHealthError;
  final TextEditingController resetConfirmation = TextEditingController();

  void dispose() {
    resetConfirmation.removeListener(_onResetConfirmationChanged);
    resetConfirmation.dispose();
  }

  void _onResetConfirmationChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_host.mounted) _host.rebuild(() {});
    });
  }

  /// Called from the core form's single `backendDeploymentProvider` listener
  /// alongside its own heartbeat/completion handling — this is the
  /// auto-recheck-on-first-target and staged-recovery-advancement logic that
  /// used to live inline in `initState`.
  void handleDeploymentStateChanged(DeploymentState? state) {
    if (!healthCheckedAutomatically &&
        (state?.targets.isNotEmpty == true ||
            _host.connectedHealthHost != null)) {
      healthCheckedAutomatically = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_host.mounted) unawaited(checkSystemHealth());
      });
    }
    if (preserveDataReinstallRequested &&
        state?.activeJob?.stage == DeploymentPhase.failed.wireName) {
      preserveDataReinstallRequested = false;
      if (_host.mounted) {
        _host.rebuild(() => healthRecoveryStage = 2);
      }
    } else if (preserveDataReinstallRequested &&
        state?.activeJob?.stage == DeploymentPhase.completed.wireName) {
      preserveDataReinstallRequested = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_host.mounted) unawaited(checkSystemHealth());
      });
    }
  }

  Future<void> checkSystemHealth() async {
    if (healthCheckRunning) return;
    _host.rebuild(() {
      healthCheckRunning = true;
      systemHealthError = null;
    });
    try {
      final report = await _host.ref
          .read(backendDeploymentProvider.notifier)
          .diagnoseLatestTarget(preferredHost: _host.connectedHealthHost);
      if (!_host.mounted) return;
      _host.rebuild(() {
        systemHealth = report;
        if (report?.overall == SystemHealthStatus.ok) {
          healthRecoveryStage = 0;
          resetConfirmation.clear();
        }
      });
    } on Object {
      if (!_host.mounted) return;
      _host.rebuild(() {
        systemHealthError =
            'The saved server could not be checked. Repair will use its saved '
            'deployment credential and will preserve all data.';
      });
    } finally {
      if (_host.mounted) _host.rebuild(() => healthCheckRunning = false);
    }
  }

  Future<void> repairSystemHealth() async {
    _host.rebuild(() {
      healthRepairRunning = true;
      systemHealthError = null;
    });
    try {
      final report = await _host.ref
          .read(backendDeploymentProvider.notifier)
          .repairLatestTarget(preferredHost: _host.connectedHealthHost);
      if (!_host.mounted) return;
      _host.rebuild(() {
        systemHealth = report;
        healthRecoveryStage = report?.overall == SystemHealthStatus.ok ? 0 : 1;
      });
    } on Object catch (error) {
      if (!_host.mounted) return;
      _host.rebuild(() {
        healthRecoveryStage = 1;
        systemHealthError = displaySetupError(error);
      });
    } finally {
      if (_host.mounted) _host.rebuild(() => healthRepairRunning = false);
    }
  }

  Future<void> reinstallSystemKeepingData() async {
    _host.rebuild(() {
      healthRepairRunning = true;
      systemHealthError = null;
      preserveDataReinstallRequested = true;
    });
    try {
      await _host.ref
          .read(backendDeploymentProvider.notifier)
          .reinstallLatestTarget(preferredHost: _host.connectedHealthHost);
    } on Object catch (error) {
      if (!_host.mounted) return;
      _host.rebuild(() {
        preserveDataReinstallRequested = false;
        healthRecoveryStage = 2;
        systemHealthError = displaySetupError(error);
      });
    } finally {
      if (_host.mounted) _host.rebuild(() => healthRepairRunning = false);
    }
  }

  Future<void> factoryResetSystem() async {
    if (resetConfirmation.text.trim() != 'RESET') return;
    _host.rebuild(() {
      healthRepairRunning = true;
      systemHealthError = null;
    });
    try {
      await _host.ref
          .read(backendDeploymentProvider.notifier)
          .reinstallLatestTarget(
            factoryReset: true,
            preferredHost: _host.connectedHealthHost,
          );
      if (_host.mounted) resetConfirmation.clear();
    } on Object catch (error) {
      if (!_host.mounted) return;
      _host.rebuild(() => systemHealthError = displaySetupError(error));
    } finally {
      if (_host.mounted) _host.rebuild(() => healthRepairRunning = false);
    }
  }

  String _healthTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  Widget _buildHealthCheckRow(SystemHealthCheck check, NmtkShellTokens tokens) {
    final icon = switch (check.status) {
      SystemHealthStatus.ok => ZetaIcons.check_circle,
      SystemHealthStatus.degraded => ZetaIcons.warning_outline,
      SystemHealthStatus.failed => ZetaIcons.error,
      SystemHealthStatus.notConfigured => ZetaIcons.info,
    };
    final color = switch (check.status) {
      SystemHealthStatus.ok => tokens.healthyColor,
      SystemHealthStatus.degraded => tokens.warningColor,
      SystemHealthStatus.failed => tokens.errorColor,
      SystemHealthStatus.notConfigured => tokens.metadataForeground,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, semanticLabel: check.status.name),
        SizedBox(width: tokens.compactGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(check.label),
              Text(check.detail),
              if (check.recovery.isNotEmpty) Text(check.recovery),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildCard(NmtkShellTokens tokens) {
    final report = systemHealth;
    final isFailed = report?.overall == SystemHealthStatus.failed;
    final isDegraded = report?.overall == SystemHealthStatus.degraded;
    final title = healthCheckRunning
        ? 'Checking the whole system…'
        : report == null
        ? 'System health has not been checked'
        : isFailed
        ? 'System repair is needed'
        : isDegraded
        ? 'System is ready with limitations'
        : 'Everything configured is working';
    final tone = isFailed
        ? NmtkTone.danger
        : isDegraded
        ? NmtkTone.warning
        : NmtkTone.success;
    return NmtkSurfaceCard(
      key: const Key('backend-system-health-card'),
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NmtkStatusBanner(
              title: title,
              content: Text(
                report == null
                    ? 'Run one check for the backend, storage, Jupyter, '
                          'snnTorch, launcher control, and configured hardware.'
                    : 'Checked ${_healthTimestamp(report.checkedAt)}.',
              ),
              tone: tone,
            ),
            if (systemHealthError != null) ...[
              SizedBox(height: tokens.compactGap),
              Text(systemHealthError!),
            ],
            if (report != null) ...[
              SizedBox(height: tokens.sectionGap),
              for (final check in report.checks) ...[
                _buildHealthCheckRow(check, tokens),
                SizedBox(height: tokens.compactGap),
              ],
            ],
            Wrap(
              spacing: tokens.compactGap,
              runSpacing: tokens.compactGap,
              children: [
                ZetaButton.outline(
                  key: const Key('backend-system-health-recheck'),
                  onPressed: healthCheckRunning || healthRepairRunning
                      ? null
                      : checkSystemHealth,
                  label: healthCheckRunning ? 'Checking…' : 'Recheck',
                ),
                if (isFailed)
                  ZetaButton(
                    key: const Key('backend-system-health-repair'),
                    onPressed: healthCheckRunning || healthRepairRunning
                        ? null
                        : repairSystemHealth,
                    label: healthRepairRunning ? 'Repairing…' : 'Repair',
                  ),
                if (healthRecoveryStage >= 1)
                  ZetaButton.outline(
                    key: const Key('backend-system-health-reinstall'),
                    onPressed: healthRepairRunning
                        ? null
                        : reinstallSystemKeepingData,
                    label: 'Reinstall and keep data',
                  ),
              ],
            ),
            if (healthRecoveryStage >= 2) ...[
              SizedBox(height: tokens.sectionGap),
              const Text(
                'The safe repair and data-preserving reinstall both failed. '
                'Factory reset permanently erases NMTK notebooks, workspaces, '
                'databases, and container volumes.',
              ),
              SizedBox(height: tokens.compactGap),
              KeyedSubtree(
                key: const Key('backend-system-health-reset-confirmation'),
                child: buildTextField(
                  resetConfirmation,
                  'Type RESET to unlock factory reset',
                ),
              ),
              SizedBox(height: tokens.compactGap),
              ZetaButton(
                key: const Key('backend-system-health-factory-reset'),
                onPressed:
                    resetConfirmation.text.trim() == 'RESET' &&
                        !healthRepairRunning
                    ? factoryResetSystem
                    : null,
                label: 'Erase and reinstall',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
