import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/akida_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/akida_handoff.dart';
import 'package:neuro_toolkit/features/neurocnl/services/akida_handoff_coordinator.dart';
import 'package:neuro_toolkit/features/neurocnl/services/host_module_navigation.dart';
import 'package:neuro_toolkit/features/neurocnl/services/platform_helper.dart' as platform;
import 'package:neuro_toolkit/features/neurocnl/widgets/shell_surface.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/labeled_parameter_grid.dart';

class AkidaDeployPanel extends ConsumerStatefulWidget {
  const AkidaDeployPanel({super.key});

  @override
  ConsumerState<AkidaDeployPanel> createState() => _AkidaDeployPanelState();
}

class _AkidaDeployPanelState extends ConsumerState<AkidaDeployPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final spec = ref.read(specTextProvider);
      ref.read(akidaDeployProvider.notifier).validate(spec);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(akidaDeployProvider);
    final notifier = ref.read(akidaDeployProvider.notifier);
    final spec = ref.watch(specTextProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        NmtkSectionCard(
          title: 'Akida Deployability',
          tone: _statusTone(state),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatus(state),
              const SizedBox(height: 10),
              Text(
                'Topology verdict: ${state.topologyVerdict}',
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  color: Zeta.of(context).colors.mainSubtle,
                ),
              ),
              if (state.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                NeurocnlMessageList(
                  messages: state.warnings,
                  tone: NmtkTone.warning,
                  icon: ZetaIcons.warning_outline,
                ),
              ],
              if (state.rejections.isNotEmpty) ...[
                const SizedBox(height: 12),
                NeurocnlMessageList(
                  messages: state.rejections,
                  tone: NmtkTone.danger,
                  icon: ZetaIcons.cancel_outline,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        NmtkSectionCard(
          title: 'Controls',
          trailing: const NeurocnlInfoButton(
            title: 'Akida Controls',
            message:
                'One-click handoff sends the Akida mapped network to Neurochip. Oversized mapped payloads stay blocked instead of falling back to a generic import route.',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Akida Version',
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  color: Zeta.of(context).colors.mainSubtle,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['akida1', 'akida2']
                    // Allowed: legacy deploy panel — pending phase-2 migration.
                    .map(
                      (version) => ChoiceChip(
                        label: Text(version.toUpperCase()),
                        selected: state.akidaVersion == version,
                        onSelected: (_) {
                          notifier.selectVersion(version);
                          notifier.validate(spec);
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              Text(
                'Weight Bit-Width',
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  color: Zeta.of(context).colors.mainSubtle,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [1, 2, 4]
                    // Allowed: legacy deploy panel — pending phase-2 migration.
                    .map(
                      (bitWidth) => ChoiceChip(
                        label: Text('$bitWidth-bit'),
                        selected: state.bitWidth == bitWidth,
                        onSelected: (_) {
                          notifier.selectBitWidth(bitWidth);
                          notifier.validate(spec);
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ZetaButton(
                      onPressed: state.phase == AkidaDeployPhase.validating
                          ? null
                          : () => notifier.validate(spec),
                      label: state.phase == AkidaDeployPhase.validating
                          ? 'Checking…'
                          : 'Run Akida Check',
                      leadingIcon: state.phase == AkidaDeployPhase.validating
                          ? null
                          : Icons
                                .developer_board_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ZetaButton.outline(
                      onPressed: state.mappedNetwork == null
                          ? null
                          : () => _openInNeurochipAkidaFlow(state),
                      leadingIcon: ZetaIcons.open_in_new_window,
                      label: 'Open in Neurochip Akida Flow',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LabeledParameterGrid(
                children: [
                  LabeledParameterRow(
                    label: 'Toolkit / board URL',
                    labelWidth: 140,
                    child: NmtkTextInput(
                      initialValue: state.hardwareUrl,
                      onChange: (v) => notifier.setHardwareUrl(v ?? ''),
                      hintText: 'http://akida.local',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        NmtkSectionCard(
          title: 'Workflow',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NmtkWorkflowStepRow(
                title: 'Scaffold package',
                subtitle: state.supportState.startsWith('exportable')
                    ? 'MetaTF scaffold path is available for this network.'
                    : 'Scaffold generation is blocked until the exportability gate passes.',
                tone: state.supportState.startsWith('exportable')
                    ? NmtkTone.success
                    : NmtkTone.neutral,
                icon: Icons
                    .inventory_2_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              ),
              NmtkWorkflowStepRow(
                title: 'Mapped network',
                subtitle: state.mappedNetwork == null
                    ? 'No mapped network returned yet.'
                    : 'Mapped package is available for downstream tooling.',
                tone: state.mappedNetwork == null
                    ? NmtkTone.warning
                    : NmtkTone.info,
                icon: Icons
                    .account_tree_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              ),
              NmtkWorkflowStepRow(
                title: 'Hardware handoff',
                subtitle: state.hardwareUrl.isEmpty
                    ? 'Optional board URL can be configured for deployment handoff.'
                    : 'Target board: ${state.hardwareUrl}',
                tone: state.hardwareUrl.isEmpty
                    ? NmtkTone.neutral
                    : NmtkTone.info,
                icon: Icons
                    .rocket_launch_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              ),
            ],
          ),
        ),
        if (state.networkSummary != null) ...[
          const SizedBox(height: 12),
          NmtkSectionCard(
            title: 'Network Summary',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildSummary(state.networkSummary!),
            ),
          ),
        ],
        if (state.mappedNetwork != null) ...[
          const SizedBox(height: 12),
          NmtkSectionCard(
            title: 'Mapped Output',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NmtkKeyValueRow(
                  label: 'Mapped populations',
                  value:
                      '${(state.mappedNetwork!['populations'] as List?)?.length ?? 0}',
                ),
                NmtkKeyValueRow(
                  label: 'Mapped connections',
                  value:
                      '${(state.mappedNetwork!['connections'] as List?)?.length ?? 0}',
                ),
              ],
            ),
          ),
        ],
        if (state.errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            state.errorMessage!,
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              color: Zeta.of(context).colors.mainNegative,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatus(AkidaDeployState state) {
    switch (state.phase) {
      case AkidaDeployPhase.ready:
        return NmtkShellStatusBadge(
          status: neurocnlStatusFromSupportState(state.supportState),
        );
      case AkidaDeployPhase.unsupported:
        return NmtkShellStatusBadge(
          status: neurocnlStatusFromVerdict('unsupported'),
        );
      case AkidaDeployPhase.failed:
        return NmtkShellStatusBadge(
          status: neurocnlStatusFromSupportState('check_failed'),
        );
      case AkidaDeployPhase.validating:
        return Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'Checking Akida mapping…',
              style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                color: Zeta.of(context).colors.mainSubtle,
              ),
            ),
          ],
        );
      case AkidaDeployPhase.idle:
        return Text(
          'No Akida verdict yet.',
          style: Zeta.of(context).textStyles.bodyMedium.copyWith(
            color: Zeta.of(context).colors.mainSubtle,
          ),
        );
    }
  }

  NmtkTone _statusTone(AkidaDeployState state) {
    return switch (state.phase) {
      AkidaDeployPhase.ready =>
        state.supportState == 'sdk_deployable'
            ? NmtkTone.success
            : NmtkTone.warning,
      AkidaDeployPhase.unsupported ||
      AkidaDeployPhase.failed => NmtkTone.danger,
      _ => NmtkTone.neutral,
    };
  }

  List<Widget> _buildSummary(Map<String, dynamic> summary) {
    return [
      NmtkKeyValueRow(
        label: 'Populations',
        value: '${summary['n_populations'] ?? '-'}',
      ),
      NmtkKeyValueRow(
        label: 'Neurons',
        value: '${summary['n_neurons'] ?? '-'}',
      ),
      NmtkKeyValueRow(
        label: 'Connections',
        value: '${summary['n_connections'] ?? '-'}',
      ),
      NmtkKeyValueRow(
        label: 'Synapses',
        value: '${summary['n_synapses'] ?? '-'}',
      ),
      NmtkKeyValueRow(
        label: 'Estimated bytes',
        value: '${summary['estimated_weight_bytes'] ?? '-'}',
      ),
    ];
  }

  Future<void> _openInNeurochipAkidaFlow(AkidaDeployState state) async {
    if (hasHostedModuleNavigator(context)) {
      if (state.mappedNetwork == null) {
        _showMessage(
          'Run the Akida check first so Studio can build the mapped-network handoff.',
          isError: true,
        );
        return;
      }

      final deepLink = AkidaHandoff.buildDeepLink(
        mappedNetwork: state.mappedNetwork!,
        bitWidth: state.bitWidth,
        akidaVersion: state.akidaVersion,
        supportState: state.supportState,
        topologyVerdict: state.topologyVerdict,
        networkSummary: state.networkSummary,
        warnings: state.warnings,
        rejections: state.rejections,
        hardwareUrl: state.hardwareUrl,
      );
      if (deepLink == null) {
        _showMessage(
          'Run the Akida check first so Studio can build the mapped-network handoff.',
          isError: true,
        );
        return;
      }

      final encodedPayload = Uri.parse(
        deepLink,
      ).queryParameters['import_akida'];
      if (encodedPayload != null &&
          encodedPayload.length > AkidaHandoff.maxEncodedPayloadLength) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Akida handoff payload is too large'),
            content: const Text(
              'This Akida mapped network is larger than the safe URL payload for '
              'one-click handoff. Studio will not fall back to the generic '
              'NetworkInput route for oversized Akida payloads.',
            ),
            actions: [
              ZetaButton.text(
                onPressed: () => Navigator.of(dialogContext).pop(),
                label: 'OK',
              ),
            ],
          ),
        );
        return;
      }

      final opened = await openModuleInHost(
        context,
        moduleId: 'Neurochip',
        deepLink: deepLink,
      );
      if (!mounted) {
        return;
      }
      if (!opened) {
        _showMessage(
          'Could not open Neurochip automatically in this suite workspace. Try reopening the module and running the handoff again.',
          isError: true,
        );
      }
      return;
    }

    const coordinator = AkidaHandoffCoordinator();
    final preparation = coordinator.prepareTarget(
      mappedNetwork: state.mappedNetwork,
      bitWidth: state.bitWidth,
      akidaVersion: state.akidaVersion,
      supportState: state.supportState,
      topologyVerdict: state.topologyVerdict,
      networkSummary: state.networkSummary,
      warnings: state.warnings,
      rejections: state.rejections,
      hardwareUrl: state.hardwareUrl,
    );

    if (!mounted) {
      return;
    }

    if (preparation.status == AkidaHandoffPreparationStatus.unavailable) {
      _showMessage(
        'Akida handoff is desktop-first. Open this module from a browser-capable suite workspace only if you need one-click navigation into Neurochip.',
        isError: true,
      );
      return;
    }

    if (preparation.status ==
        AkidaHandoffPreparationStatus.mappingUnavailable) {
      _showMessage(
        preparation.errorMessage ??
            'Run the Akida check first so Studio can build a mapped-network handoff.',
        isError: true,
      );
      return;
    }

    final target = preparation.target!;
    if (AkidaHandoff.exceedsSafePayload(target)) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Akida handoff payload is too large'),
          content: const Text(
            'This Akida mapped network is larger than the safe URL payload for '
            'one-click handoff. Studio will not fall back to the generic '
            'NetworkInput route for oversized Akida payloads.',
          ),
          actions: [
            ZetaButton.text(
              onPressed: () => Navigator.of(dialogContext).pop(),
              label: 'OK',
            ),
          ],
        ),
      );
      return;
    }

    final opened = await platform.openUrl(target.url.toString());
    if (!mounted) {
      return;
    }
    if (!opened) {
      _showMessage(
        'Could not open Neurochip automatically from this workspace. Try again from a browser-capable suite workspace.',
        isError: true,
      );
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      isError
          ? NmtkSnackBars.error(context, message)
          : NmtkSnackBars.success(context, message),
    );
  }
}
