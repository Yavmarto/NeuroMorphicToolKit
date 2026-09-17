library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/hardware_reachability_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_pynq_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/pynq_execution_pane/pynq_execution_pane.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/pynq_setup_pane/pynq_setup_pane.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/studio_standard_deploy_page/studio_standard_deploy_page.dart';

class StudioPynqWorkspace extends ConsumerStatefulWidget {
  const StudioPynqWorkspace({
    super.key,
    required this.selectedDeviceLabel,
    required this.selectedDeviceData,
    required this.isCompact,
    this.onManageHardwareTarget,
  });

  final String? selectedDeviceLabel;
  final Object? selectedDeviceData;
  final bool isCompact;
  final ValueChanged<String>? onManageHardwareTarget;

  @override
  ConsumerState<StudioPynqWorkspace> createState() =>
      _StudioPynqWorkspaceState();
}

class _StudioPynqWorkspaceState extends ConsumerState<StudioPynqWorkspace> {
  /// Validates the spec and loads a sample once per (board, workspace, spec).
  ///
  /// Keyed rather than run on every build because each half is a network round
  /// trip — and the spec is in the key because a verdict for a different
  /// network is worse than no verdict. The key lives in the provider, not here:
  /// this widget is disposed when the user switches pipeline steps, so a
  /// widget-local key made Deploy → Review → Deploy repeat the whole pass.
  ///
  /// It deliberately does *not* call `checkReadiness`. The board's preflight
  /// costs about twenty seconds — it spawns an interpreter that imports `pynq`
  /// on the board — and [pynqBoardReadinessProvider] has already run one to
  /// produce the board this pane is showing. Asking again on arrival bought
  /// nothing and left the pane spinning with Deploy greyed out; the "Check
  /// readiness" button is still there for when the user wants a fresh answer.
  void _schedulePreparation(
    PynqPairedBoard? board,
    String spec,
    String workspaceName,
  ) {
    final key = '${board?.id ?? 'none'}::$workspaceName::${spec.hashCode}';
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final notifier = ref.read(studioPynqDeployProvider.notifier);
      // Claimed here rather than during build: writing to a provider while the
      // tree is building throws. Callbacks run in order, so only the first of a
      // burst of rebuilds gets through.
      if (!notifier.claimPreparation(key)) return;
      if (board != null &&
          ref.read(studioPynqDeployProvider).selectedBoard?.id != board.id) {
        notifier.selectBoard(board);
      }
      await notifier.validate(spec, workspaceFolder: workspaceName);
      if (!mounted) return;
      // The stimulus the board can actually be judged on. A failure here is
      // reported beside the picker, not as a deploy error.
      await notifier.loadDatasetSample(workspaceName);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(studioPynqDeployProvider);
    final readinessBoard = ref.watch(pynqBoardReadinessProvider).value;
    final selectedBoard =
        provider.selectedBoard ??
        (widget.selectedDeviceData is PynqPairedBoard
            ? widget.selectedDeviceData as PynqPairedBoard
            : null) ??
        readinessBoard;
    final spec = ref.watch(specTextProvider);
    final workspaceName = ref.watch(workspaceProvider).workspaceName;
    _schedulePreparation(selectedBoard, spec, workspaceName);

    return StudioStandardDeployPage(
      title: widget.isCompact && selectedBoard != null
          ? 'PYNQ-Z2 · ${selectedBoard.displayName}'
          : 'PYNQ-Z2 Overlay',
      isCompact: widget.isCompact,
      setup: PynqSetupPane(
        provider: provider,
        selectedBoard: selectedBoard,
        onManageHardwareTarget: widget.onManageHardwareTarget,
      ),
      inference: PynqExecutionPane(
        provider: provider,
        isCompact: widget.isCompact,
      ),
    );
  }
}
