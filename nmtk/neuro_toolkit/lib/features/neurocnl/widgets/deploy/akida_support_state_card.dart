import 'package:neuro_toolkit/ui_core/shell_tokens.dart';
import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:neuro_toolkit/ui_core/models/akida_deployment_model.dart';

/// Displays a NeuroCNL [AkidaSupportState] as a coloured summary card.
///
/// Shows the state icon and label, optional Akida version and topology
/// verdict badges, warnings (amber), rejection reasons (red), and a
/// network summary line.  Suitable for the Akida deploy screen and any
/// other surface that needs a compact exportability readout.
///
/// Visual semantics:
/// - Indigo for scaffold states (distinct from PYNQ teal and Teensy green)
/// - Amber for near-capacity warnings
/// - Red for unsupported / SDK unavailable
/// - Green for SDK-deployed
class AkidaSupportStateCard extends StatelessWidget {
  final AkidaSupportState supportState;
  final List<String> warnings;
  final List<String> rejections;
  final String? akidaVersion;
  final String? topologyVerdict;

  /// Optional network summary fields shown below warnings/rejections.
  final Map<String, dynamic>? networkSummary;

  /// Message shown when [supportState] is [AkidaSupportState.sdkNotDeployable].
  final String scaffoldOnlyNotice;

  const AkidaSupportStateCard({
    super.key,
    required this.supportState,
    this.warnings = const [],
    this.rejections = const [],
    this.akidaVersion,
    this.topologyVerdict,
    this.networkSummary,
    this.scaffoldOnlyNotice = 'Akida SDK not verified — scaffold package only.',
  });

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final color = supportState.colorFor(tokens);

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderRow(context, color),
            if (supportState == AkidaSupportState.sdkNotDeployable)
              _buildScaffoldOnlyNotice(context),
            ..._buildWarningsAndRejections(context, tokens),
            if (networkSummary != null && networkSummary!.isNotEmpty)
              _buildNetworkSummary(context),
            if (topologyVerdict != null && topologyVerdict!.isNotEmpty)
              _buildTopologyVerdict(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow(BuildContext context, Color color) {
    return Row(
      children: [
        Icon(supportState.icon, color: color, size: 28),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            supportState.label,
            style: Zeta.of(
              context,
            ).textStyles.titleMedium.copyWith(color: color),
          ),
        ),
        if (akidaVersion != null) ZetaAssistChip(label: akidaVersion!),
      ],
    );
  }

  Widget _buildScaffoldOnlyNotice(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 36),
      child: Text(
        scaffoldOnlyNotice,
        style: Zeta.of(context).textStyles.bodyMedium.apply(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  List<Widget> _buildWarningsAndRejections(
    BuildContext context,
    NmtkShellTokens tokens,
  ) {
    return [
      if (warnings.isNotEmpty) ...[
        const SizedBox(height: 8),
        ...warnings.map(
          (w) => Padding(
            padding: const EdgeInsets.only(left: 36, bottom: 4),
            child: Text(
              '⚠ $w',
              style: Zeta.of(
                context,
              ).textStyles.bodyMedium.apply(color: tokens.warningColor),
            ),
          ),
        ),
      ],
      if (rejections.isNotEmpty) ...[
        const SizedBox(height: 8),
        ...rejections.map(
          (r) => Padding(
            padding: const EdgeInsets.only(left: 36, bottom: 4),
            child: Text(
              '✗ $r',
              style: Zeta.of(
                context,
              ).textStyles.bodyMedium.apply(color: tokens.errorColor),
            ),
          ),
        ),
      ],
    ];
  }

  Widget _buildNetworkSummary(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 36),
      child: Text(
        _formatNetworkSummary(networkSummary!),
        style: Zeta.of(context).textStyles.bodySmall,
      ),
    );
  }

  Widget _buildTopologyVerdict(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 36),
      child: Text(
        'Topology: $topologyVerdict',
        style: Zeta.of(context).textStyles.bodySmall.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  String _formatNetworkSummary(Map<String, dynamic> summary) {
    final parts = <String>[];
    if (summary['n_neurons'] != null) {
      parts.add('${summary['n_neurons']} neurons');
    }
    if (summary['n_synapses'] != null) {
      parts.add('${summary['n_synapses']} synapses');
    }
    if (summary['estimated_memory_kb'] != null) {
      final mem = (summary['estimated_memory_kb'] as num).toStringAsFixed(1);
      parts.add('$mem KB est.');
    }
    return parts.join(' · ');
  }
}
