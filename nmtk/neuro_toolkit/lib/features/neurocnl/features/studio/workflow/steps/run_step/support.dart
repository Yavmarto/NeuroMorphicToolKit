import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/notebook_step/notebook_step.dart';

void openStudioNotebook(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        appBar: AppBar(
          title: const Text('Notebook'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(ZetaIcons.close),
              tooltip: 'Close',
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
        body: const NotebookStep(),
      ),
    ),
  );
}

/// `notApplicable` is not a failure: the platform's notebook was generated and
/// is readable in Jupyter, but it has no training loop, so Play deliberately
/// did not execute it. Keeping it distinct from `complete` and `error` is what
/// stops a deploy-only target (Akida, Sinabs, …) either faking success or
/// showing a red dot the user cannot act on.
enum TrainingStatus { idle, running, complete, error, notApplicable }

/// Fixed desktop dimensions for the Live Metrics portion of the shared
/// bottom-right canvas dock. The Inspector is rendered above this panel by
/// [CanvasScreen], keeping both utilities in one predictable location.
const double kMetricsDockWidth = 240.0;
const double kMetricsDockHeight = 280.0;
const double kMetricsDockInset = kMetricsDockWidth + 12;

// ── Floating run action bar ─────────────────────────────────────────────

// ── Metrics sidebar ─────────────────────────────────────────────────────

// ── Spike-rate legend overlay ───────────────────────────────────────────
