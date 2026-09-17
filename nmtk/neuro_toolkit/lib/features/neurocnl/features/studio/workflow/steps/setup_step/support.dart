import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/workflow_feature.dart';

/// Status dot next to a selected target, with the reason on hover.
///
/// Akida is routed differently from every other target on purpose. The backend's
/// `/targets/{id}/reachability` probe runs *inside the backend container* — an
/// `import akida` plus a local device enumeration — but Studio deploys Akida to a
/// paired remote host over SSH. Asking the container therefore reported "not
/// reachable" for a perfectly healthy card, which made this dot permanently red
/// and unexplained. Akida now reads launcher control's per-host preflight, which
/// is the same source the Akida Runtime panel uses.
/// What ticking a target actually does, in one line.
///
/// Ticking a platform used to mean three unrelated things at once — generate a
/// notebook, run it, and enable hardware pairing — so there was no correct
/// answer to "should I tick Akida?". Saying it on the tile is the fix.
String platformRoleDescription(String id) {
  if (targetIsTrainable(id)) {
    return 'Play trains on this target.';
  }
  final pairs = isHardwareTargetWithManageFlowId(id);
  return pairs
      ? 'Play does not train this — it generates a readable notebook and lets '
            'you pair a host here. Deploy from Results → Deploy to Hardware.'
      : 'Play does not train this — it generates a readable notebook for '
            'inspection. Train on snnTorch, then export to this target.';
}

bool isHardwareTargetWithManageFlowId(String id) =>
    id == 'akida' || id == 'pynq' || id == 'sc_neurocore_fpga';

/// Targets whose readiness only launcher control can answer.
///
/// Both are remote machines reached over SSH, so the backend container's own
/// `/targets/{id}/reachability` probe cannot see them and always reports
/// unreachable. These get the launcher-backed provider plus a tappable
/// re-check instead.
bool usesLauncherReadinessProbe(String id) => id == 'akida' || id == 'pynq';

/// "Training" / "Deploy only" chip, so the distinction is visible before the
/// user commits to a tickbox.

const scratchBenchmarks = <BenchmarkOption>[
  BenchmarkOption(
    id: 'keyword_spotting',
    label: 'Keyword spotting',
    subtitle: 'Speech / wake-word benchmark',
  ),
  BenchmarkOption(
    id: 'ecg_classification',
    label: 'ECG classification',
    subtitle: 'Biomedical signal benchmark',
  ),
  BenchmarkOption(
    id: 'dvs_gesture',
    label: 'DVS gesture',
    subtitle: 'Event-camera gesture benchmark',
  ),
  BenchmarkOption(
    id: 'grip_stability',
    label: 'Grip stability',
    subtitle: 'Motor-control benchmark',
  ),
  BenchmarkOption(
    id: 'primate_reaching',
    label: 'Primate reaching',
    subtitle: 'Closed-loop control benchmark',
  ),
];

// ── Folder section ──────────────────────────────────────────────

// ── File tile ───────────────────────────────────────────────────

String formatBytesStatic(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

// ── Download progress bar ───────────────────────────────────────
