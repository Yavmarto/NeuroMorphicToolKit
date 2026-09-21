library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/deploy_results_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/support.dart';

class CompareTargetsDialog extends ConsumerStatefulWidget {
  const CompareTargetsDialog({super.key, required this.initialSelection});

  final Set<String> initialSelection;

  @override
  ConsumerState<CompareTargetsDialog> createState() =>
      _CompareTargetsDialogState();
}

class _CompareTargetsDialogState extends ConsumerState<CompareTargetsDialog> {
  late final Set<String> _selected = {...widget.initialSelection};

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final textStyles = Zeta.of(context).textStyles;
    return AlertDialog(
      insetPadding: NmtkDialogSurface.insetPadding(context),
      title: const Text('Compare targets'),
      content: ConstrainedBox(
        // Cap alone (no nested fixed-width box): NmtkDialogSurface.constraints
        // already returns screenWidth-derived maxWidth on compact viewports,
        // so a hard-coded inner SizedBox(width: 360) would just fight it.
        constraints: NmtkDialogSurface.constraints(context, maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final id in reviewableTargets)
                Builder(
                  builder: (context) {
                    final hasResult = ref.watch(
                      deployTargetHasResultProvider(id),
                    );
                    return CheckboxListTile(
                      // No `dense: true` — that drops the row below the
                      // 44 px minimum tap target on touch/mobile.
                      controlAffinity: ListTileControlAffinity.leading,
                      value: hasResult && _selected.contains(id),
                      title: Text(targetLabel(id)),
                      subtitle: hasResult
                          ? null
                          : Text(
                              'Not run yet',
                              style: textStyles.bodySmall.copyWith(
                                color: colors.mainSubtle,
                              ),
                            ),
                      onChanged: hasResult
                          ? (checked) => setState(() {
                              if (checked ?? false) {
                                _selected.add(id);
                              } else {
                                _selected.remove(id);
                              }
                            })
                          : null,
                    );
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        ZetaButton.text(
          onPressed: () => Navigator.of(context).pop(),
          label: 'Cancel',
        ),
        ZetaButton.text(
          onPressed: () => Navigator.of(context).pop(_selected),
          label: 'Compare',
        ),
      ],
    );
  }
}
