library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

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
      title: const Text('Compare targets'),
      content: SizedBox(
        width: 360,
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
                    dense: true,
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Compare'),
        ),
      ],
    );
  }
}
