import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';

/// Shows a small dialog for editing Pipeline tab settings not tied to any
/// single DAG node — currently the training epoch count and random seed.
///
/// `PipelineConfig.epochs`/`.seed` (see `models/canvas/pipeline_config.dart`)
/// are the sole source of truth for these settings; the Validation Loop
/// node's property panel deliberately does not expose epochs, to avoid two
/// divergent knobs for the same setting.
Future<void> showPipelineSettingsDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _PipelineSettingsDialog(),
  );
}

class _PipelineSettingsDialog extends ConsumerStatefulWidget {
  const _PipelineSettingsDialog();

  @override
  ConsumerState<_PipelineSettingsDialog> createState() =>
      _PipelineSettingsDialogState();
}

class _PipelineSettingsDialogState
    extends ConsumerState<_PipelineSettingsDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController epochsController;
  late final TextEditingController seedController;

  @override
  void initState() {
    super.initState();
    final pipeline = ref.read(canvasProvider).pipeline;
    epochsController = TextEditingController(text: pipeline.epochs.toString());
    seedController = TextEditingController(text: pipeline.seed.toString());
  }

  @override
  void dispose() {
    epochsController.dispose();
    seedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: NmtkDialogSurface.insetPadding(context),
      shape: RoundedRectangleBorder(borderRadius: NmtkDesignTokens.dialogShape),
      title: const Text('Pipeline Settings'),
      content: NmtkDialogSurface.wrapScrollable(
        context,
        Form(
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
      ),
      actions: [
        ZetaButton.text(
          onPressed: () => Navigator.of(context).pop(),
          label: 'Cancel',
        ),
        ZetaButton.text(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            final epochs = int.parse(epochsController.text);
            final seed = int.parse(seedController.text);
            final pipeline = ref.read(canvasProvider).pipeline;
            ref
                .read(canvasProvider.notifier)
                .updatePipeline(pipeline.copyWith(epochs: epochs, seed: seed));
            Navigator.of(context).pop();
          },
          label: 'Save',
        ),
      ],
    );
  }
}
