import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/pynq_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/deploy/pynq_support_state_card.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/shell_surface.dart';

/// PYNQ-Z2 exportability check panel. Verdict-only in this build: the FINN
/// bitstream-compile stage is not yet wired (see `docs/support_matrix.md`),
/// so this panel reports export eligibility and network sizing only — it
/// does not produce or flash an overlay onto a physical board.
class PynqDeployPanel extends ConsumerStatefulWidget {
  const PynqDeployPanel({super.key, this.showSupportState = true});

  /// When false the verdict card is omitted — the Deploy step passes this
  /// because the verdict is rendered in the Review step instead.
  final bool showSupportState;

  @override
  ConsumerState<PynqDeployPanel> createState() => _PynqDeployPanelState();
}

class _PynqDeployPanelState extends ConsumerState<PynqDeployPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final spec = ref.read(specTextProvider);
      ref.read(pynqDeployControllerProvider.notifier).validate(spec);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pynqDeployControllerProvider);
    final notifier = ref.read(pynqDeployControllerProvider.notifier);
    final spec = ref.watch(specTextProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.showSupportState) ...[
          NmtkSectionCard(
            title: 'PYNQ-Z2 Deployability',
            trailing: const NeurocnlInfoButton(
              title: 'PYNQ-Z2 Export',
              message:
                  'NeuroStudio checks the network against the fixed PYNQ overlay-v1 '
                  'contract (max synapse count and supported weight bit-widths). '
                  'Overlay/bitstream generation (FINN) is not implemented yet — '
                  'this check reports export eligibility only.',
            ),
            child: state.phase == PynqDeployPhase.validating
                ? Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Checking PYNQ-Z2 mapping…',
                        style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                          color: Zeta.of(context).colors.mainSubtle,
                        ),
                      ),
                    ],
                  )
                : state.phase == PynqDeployPhase.idle
                ? Text(
                    'No PYNQ-Z2 verdict yet.',
                    style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                      color: Zeta.of(context).colors.mainSubtle,
                    ),
                  )
                : PynqSupportStateCard(
                    supportState: state.supportState,
                    warnings: state.warnings,
                    rejections: state.rejections,
                    networkSummary: state.networkSummary,
                  ),
          ),
          const SizedBox(height: 12),
        ],
        NmtkSectionCard(
          title: 'Controls',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Weight Bit-Width',
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  color: Zeta.of(context).colors.mainSubtle,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                // Fixed overlay-v1 contract — mirrors PYNQ_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS
                // in neurocnl/neurocnl/contracts/pynq_deployment_contract.py.
                children: [8, 16, 32]
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
              ZetaButton(
                onPressed: state.phase == PynqDeployPhase.validating
                    ? null
                    : () => notifier.validate(spec),
                label: state.phase == PynqDeployPhase.validating
                    ? 'Checking…'
                    : 'Run PYNQ Check',
                leadingIcon: state.phase == PynqDeployPhase.validating
                    ? null
                    : Icons
                          .developer_board_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              ),
              const SizedBox(height: 12),
              Text(
                'PYNQ export is verdict-only in this build; overlay/bitstream '
                'generation (FINN) is not yet implemented.',
                style: Zeta.of(context).textStyles.bodySmall.copyWith(
                  color: Zeta.of(context).colors.mainSubtle,
                ),
              ),
            ],
          ),
        ),
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
}
