import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/models/pynq_deployment_model.dart';

/// Displays a [PynqSupportState] as a coloured summary card.
///
/// Shows the state icon and label, an optional list of warnings (amber),
/// and an optional list of rejection reasons (red).  Suitable for use in
/// both the PYNQ deploy screen and any other surface that needs a compact
/// exportability readout.
class PynqSupportStateCard extends StatelessWidget {
  final PynqSupportState supportState;
  final List<String> warnings;
  final List<String> rejections;

  /// Optional network summary fields shown below warnings/rejections.
  final Map<String, dynamic>? networkSummary;

  const PynqSupportStateCard({
    super.key,
    required this.supportState,
    this.warnings = const [],
    this.rejections = const [],
    this.networkSummary,
  });

  @override
  Widget build(BuildContext context) {
    final color = supportState.color;

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(supportState.icon, color: color, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    supportState.label,
                    style: Zeta.of(context).textStyles.titleMedium.copyWith(color: color),
                  ),
                ),
              ],
            ),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...warnings.map(
                (w) => Padding(
                  padding: const EdgeInsets.only(left: 36, bottom: 4),
                  child: Text(
                    '⚠ $w',
                    style: Zeta.of(context).textStyles.bodyMedium.apply(
                      color: Zeta.of(context).colors.mainWarning,
                    ),
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
                    style: Zeta.of(context).textStyles.bodyMedium.apply(
                      color: Zeta.of(context).colors.mainNegative,
                    ),
                  ),
                ),
              ),
            ],
            if (networkSummary != null && networkSummary!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 36),
                child: Text(
                  _formatNetworkSummary(networkSummary!),
                  style: Zeta.of(context).textStyles.bodySmall,
                ),
              ),
            ],
          ],
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
