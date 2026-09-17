import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' show ZetaButton;

import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/template.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canonical_doc_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/validation_provider.dart' as canvas_val;
import 'package:neuro_toolkit/features/neurocnl/providers/hardware_config_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';

Future<void> applyTemplateToWorkspace(
  WidgetRef ref,
  CnlTemplate template,
) async {
  ref
      .read(selectedHardwareConfigProvider.notifier)
      .setState(template.hardwareConfig);
  await ref.read(canonicalDocProvider.notifier).updateFromCnl(template.spec);
  await ref
      .read(pipelineProvider.notifier)
      .runParseAndValidate(
        template.spec,
        backendOverride: template.validationBackend,
      );
  // Validate the populated canvas graph so the validation panel reflects
  // the template state immediately. Fire-and-forget — same pattern as NIR
  // write-back — to avoid blocking the template load on the HTTP round-trip.
  final graph = ref.read(canvasProvider).graph;
  if (graph.nodes.isNotEmpty) {
    unawaited(ref.read(canvas_val.validationProvider.notifier).validate(graph));
  }
}

Future<bool> confirmTemplateReplacement(
  BuildContext context,
  WidgetRef ref,
  CnlTemplate template,
) async {
  final activeFile = ref.read(workspaceProvider).activeFile;
  if (activeFile == null ||
      !activeFile.dirty ||
      (activeFile.canonicalDocument?.cnlText ?? '') == template.spec) {
    return true;
  }

  final l10n = AppLocalizations.of(context);
  final shouldReplace = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n?.templateGallery ?? 'Template Gallery'),
      content: Text(
        'Loading ${template.name} will replace unsaved changes in ${activeFile.name}.',
      ),
      actions: [
        ZetaButton.text(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          label: 'Keep editing',
        ),
        ZetaButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          label: 'Load template',
        ),
      ],
    ),
  );

  return shouldReplace ?? false;
}
