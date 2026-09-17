import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/studio_pynq_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/deploy/pynq_support_state_card.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/studio_shared.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/pynq_setup_pane/pynq_weight_provenance.dart';

class PynqSetupPane extends ConsumerWidget {
  const PynqSetupPane({
    super.key,
    required this.provider,
    required this.selectedBoard,
    this.onManageHardwareTarget,
  });

  final StudioPynqDeployState provider;
  final PynqPairedBoard? selectedBoard;
  final ValueChanged<String>? onManageHardwareTarget;

  /// Whether the board still needs its agent installed.
  ///
  /// `unpaired` and `reachable` mean SSH works but nothing is installed yet;
  /// `provisionFailed` means a previous attempt died and retrying is the fix.
  static bool _needsProvision(PynqBoardState state) => switch (state) {
    PynqBoardState.unpaired ||
    PynqBoardState.reachable ||
    PynqBoardState.provisionFailed => true,
    _ => false,
  };

  static bool _needsOverlay(PynqPairedBoard board) => switch (board.state) {
    PynqBoardState.runtimeInstalled ||
    PynqBoardState.overlayMissing ||
    PynqBoardState.preflightFailed ||
    PynqBoardState.degradedOptionalCapability =>
      board.overlayVersion.trim().isEmpty,
    _ => false,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(studioPynqDeployProvider.notifier);
    final textStyles = Zeta.of(context).textStyles;
    final colors = Zeta.of(context).colors;
    final board = selectedBoard;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Board setup',
          style: textStyles.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (board == null) ...[
          const StudioPhaseBanner(
            label: 'No PYNQ-Z2 board is paired.',
            tone: NmtkTone.warning,
          ),
          const SizedBox(height: 8),
          if (onManageHardwareTarget != null)
            FilledButton.icon(
              key: const Key('pynq-pair-board'),
              onPressed: () => onManageHardwareTarget!('pynq'),
              icon: const Icon(Icons.settings_ethernet_outlined, size: 18),
              label: const Text('Pair or select board'),
            ),
        ] else ...[
          StudioPhaseBanner(
            label: board.state == PynqBoardState.ready
                ? 'Overlay ready on the FPGA'
                : board.state.label,
            tone: board.state == PynqBoardState.ready
                ? NmtkTone.success
                : NmtkTone.warning,
          ),
          const SizedBox(height: 8),
          NmtkKeyValueRow(label: 'Board', value: board.displayName),
          NmtkKeyValueRow(
            label: 'Address',
            value: '${board.username}@${board.host}:${board.sshPort}',
          ),
          NmtkKeyValueRow(
            label: 'Overlay',
            value: board.overlayVersion.isEmpty
                ? 'Not installed'
                : board.overlayVersion,
          ),
          if (board.lastRuntimeMode.trim().isNotEmpty)
            NmtkKeyValueRow(label: 'Runtime', value: board.lastRuntimeMode),
          if (board.lastPreflightMessage.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                board.lastPreflightMessage.trim(),
                style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
              ),
            ),
          // A missing overlay on the *backend* is a broken install, not
          // something the user can fix on the board — name the files so a
          // support conversation has something concrete to go on.
          if (provider.overlayPackage != null &&
              !provider.overlayPackage!.ready) ...[
            const SizedBox(height: 12),
            const StudioStatusLine(
              message: 'The backend has no overlay to install.',
              tone: NmtkTone.danger,
            ),
            for (final issue in provider.overlayPackage!.issues)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $issue', style: textStyles.bodySmall),
              ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              NmtkOutlinedButton(
                key: const Key('pynq-check-readiness'),
                onPressed: provider.isBusy ? null : notifier.checkReadiness,
                icon: ZetaIcons.check_circle_outline,
                label: 'Check readiness',
              ),
              if (_needsProvision(board.state))
                NmtkPrimaryButton(
                  key: const Key('pynq-provision-board'),
                  onPressed: provider.isBusy ? null : notifier.provisionBoard,
                  icon: ZetaIcons.download,
                  label: 'Install board runtime',
                ),
              if (_needsOverlay(board))
                NmtkPrimaryButton(
                  key: const Key('pynq-install-overlay'),
                  onPressed: provider.isBusy ? null : notifier.installOverlay,
                  icon: ZetaIcons.cloud_upload,
                  label: 'Install overlay',
                ),
              NmtkOutlinedButton(
                key: const Key('pynq-restart-runtime'),
                onPressed: provider.isBusy ? null : notifier.restartRuntime,
                icon: ZetaIcons.refresh,
                label: 'Restart runtime',
              ),
              if (onManageHardwareTarget != null)
                NmtkOutlinedButton(
                  onPressed: () => onManageHardwareTarget!('pynq'),
                  label: 'Change board',
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Divider(color: colors.borderSubtle),
        const SizedBox(height: 16),
        Text(
          'Network fit',
          style: textStyles.labelLarge.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (provider.exportResult == null)
          Text(
            'Checking this network against the overlay…',
            style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
          )
        else ...[
          PynqSupportStateCard(
            supportState: provider.exportResult!.supportState,
            warnings: provider.exportResult!.warnings,
            rejections: provider.exportResult!.rejectionReasons,
            networkSummary: provider.exportResult!.networkSummary,
          ),
          const SizedBox(height: 12),
          PynqWeightProvenance(provider: provider),
        ],
        // Progress and errors for setup only. A run reports itself under the
        // button that started it, which is in the other pane.
        if (provider.phase != StudioPynqDeployPhase.running &&
            provider.phase != StudioPynqDeployPhase.verifying) ...[
          if (provider.activityMessage != null ||
              provider.errorMessage != null) ...[
            const SizedBox(height: 16),
            StudioStatusLine(
              message: provider.errorMessage ?? provider.activityMessage!,
              tone: provider.errorMessage != null
                  ? NmtkTone.danger
                  : provider.isBusy
                  ? NmtkTone.neutral
                  : NmtkTone.success,
              loading: provider.isBusy,
            ),
          ],
          if (provider.warningMessage != null) ...[
            const SizedBox(height: 8),
            StudioStatusLine(
              message: provider.warningMessage!,
              tone: NmtkTone.warning,
            ),
          ],
        ],
      ],
    );
  }
}
