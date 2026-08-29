import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';

/// Shows a small dialog for editing Pipeline tab settings not tied to any
/// single DAG node — currently the training epoch count and random seed.
///
/// `PipelineConfig.epochs`/`.seed` (see `models/canvas/pipeline_config.dart`)
/// are the sole source of truth for these settings; the Validation Loop
/// node's property panel deliberately does not expose epochs, to avoid two
/// divergent knobs for the same setting.
Future<void> showPipelineSettingsDialog(BuildContext context, WidgetRef ref) {
  final pipeline = ref.read(canvasProvider).pipeline;
  final formKey = GlobalKey<FormState>();
  final epochsController = TextEditingController(
    text: pipeline.epochs.toString(),
  );
  final seedController = TextEditingController(text: pipeline.seed.toString());

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: NmtkDesignTokens.dialogShape),
      title: const Text('Pipeline Settings'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: epochsController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Epochs'),
              validator: (value) {
                final parsed = int.tryParse(value ?? '');
                if (parsed == null || parsed < 1 || parsed > 2000) {
                  return 'Enter a number between 1 and 2000';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: seedController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Random Seed',
                helperText:
                    'Pins weight init / data shuffling for reproducible runs',
              ),
              validator: (value) {
                final parsed = int.tryParse(value ?? '');
                if (parsed == null || parsed < 0) {
                  return 'Enter a non-negative integer';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            final epochs = int.parse(epochsController.text);
            final seed = int.parse(seedController.text);
            ref
                .read(canvasProvider.notifier)
                .updatePipeline(pipeline.copyWith(epochs: epochs, seed: seed));
            Navigator.of(dialogContext).pop();
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
