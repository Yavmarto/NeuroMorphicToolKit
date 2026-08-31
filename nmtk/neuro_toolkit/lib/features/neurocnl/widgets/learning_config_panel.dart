import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/widgets/labeled_parameter_grid.dart';

/// Reusable form panel for sleep-training (learning) configuration.
///
/// Exposes [epochs] and [homeostasisFactor] via callbacks so the parent
/// can read the latest values when submitting.
class LearningConfigPanel extends StatelessWidget {
  final int epochs;
  final double homeostasisFactor;
  final ValueChanged<int> onEpochsChanged;
  final ValueChanged<double> onHomeostasisChanged;

  const LearningConfigPanel({
    super.key,
    required this.epochs,
    required this.homeostasisFactor,
    required this.onEpochsChanged,
    required this.onHomeostasisChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Epochs slider
        LabeledParameterRow(
          label: 'Epochs',
          labelWidth: 130,
          child: Row(
            children: [
              Expanded(
                child: Slider(
                  value: epochs.toDouble(),
                  min: 1,
                  max: 50,
                  divisions: 49,
                  onChanged: (v) => onEpochsChanged(v.round()),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '$epochs',
                  style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                    color: Zeta.of(context).colors.mainPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Homeostasis factor
        LabeledParameterRow(
          label: 'Homeostasis Factor',
          labelWidth: 130,
          child: SizedBox(
            width: 120,
            child: NmtkTextInput(
              initialValue: homeostasisFactor.toString(),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              // ZETA-MIGRATION-TODO: inputFormatters has no ZetaTextInput equivalent
              hintText: '0.001–0.1',
              onChange: (v) {
                final parsed = double.tryParse(v ?? '');
                if (parsed != null && parsed >= 0.001 && parsed <= 0.1) {
                  onHomeostasisChanged(parsed);
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}
