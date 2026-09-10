import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/nir_types_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/simulation_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/coactivation_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_view_mode_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_mode_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/coactivation_correlation.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/network_layer_search.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/network_2_5d_view.dart';

/// Studio host for the network view: reads the current [CanvasGraph] from
/// `canvasProvider`, the live per-tick spike rates from
/// `trainingModeProvider`, or the stored `PreviewPlayback` for post-run
/// review, and hands them to the provider-free [Network25DView] together with
/// the co-activation edge strengths.
///
/// This is the CEL-141 wiring slot, rebuilt on top of CEL-140's correlation
/// engine. The visual treatment (spherical/orbital layout, orbit camera,
/// glow core) is layered on by CEL-144a-d; this widget owns only the data
/// plumbing and mode switching. The header also hosts the CEL-144d
/// filter-by-layer search, which selects the focused layer in the graph.
class NetworkStudioView extends ConsumerStatefulWidget {
  const NetworkStudioView({super.key, this.showHeader = true});

  /// Whether to draw the mode/cluster header above the canvas.
  final bool showHeader;

  @override
  ConsumerState<NetworkStudioView> createState() => _NetworkStudioViewState();
}

class _NetworkStudioViewState extends ConsumerState<NetworkStudioView> {
  String? _selectedNodeId;

  @override
  Widget build(BuildContext context) {
    final graph = ref.watch(canvasProvider.select((state) => state.graph));
    final liveRates = ref.watch(trainingModeProvider);
    final playback = ref.watch(
      simulationProvider.select((state) => state.playback),
    );
    final currentTime = ref.watch(
      simulationProvider.select((state) => state.currentTime),
    );
    final nirTypes = ref.watch(nirNodeTypeMapProvider);
    final coactivation = ref.watch(coactivationProvider);

    // Live training takes precedence over a stored review snapshot: when live
    // rates appear while reviewing, drop back to live mode. The provider
    // itself never leaves review on a live write, so this is the one place
    // that decides precedence.
    ref.listen<Map<String, double>?>(trainingModeProvider, (previous, next) {
      final isLive = next != null && next.isNotEmpty;
      if (isLive && ref.read(coactivationProvider).isReview) {
        ref.read(coactivationProvider.notifier).reset();
      }
    });

    final hasLive = liveRates != null && liveRates.isNotEmpty;
    final reviewRates = coactivation.reviewRates;

    final Map<String, double>? activity;
    if (hasLive) {
      activity = liveRates;
    } else if (reviewRates != null) {
      activity = reviewRates.ratesAtTime(currentTime);
    } else {
      activity = null;
    }

    final edgeStrengths = coactivationEdgeStrengths(
      graph,
      coactivation.snapshot,
    );

    // Drop a selection whose layer has left the graph, without mutating state
    // during build.
    final selectedNodeId = graph.nodes.any((node) => node.id == _selectedNodeId)
        ? _selectedNodeId
        : null;

    void selectNode(CanvasNode? node) =>
        setState(() => _selectedNodeId = node?.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader)
          _NetworkHeader(
            hasLive: hasLive,
            hasPlayback: playback != null,
            clusterCount: coactivation.snapshot?.clusters.length ?? 0,
            nodes: graph.nodes,
            selectedNodeId: selectedNodeId,
            onNodeSelected: selectNode,
          ),
        Expanded(
          child: Network25DView(
            graph: graph,
            activity: activity,
            edgeStrengths: edgeStrengths.isEmpty ? null : edgeStrengths,
            nirTypes: nirTypes,
            selectedNodeId: selectedNodeId,
            onNodeSelected: selectNode,
          ),
        ),
      ],
    );
  }
}

class _NetworkHeader extends StatelessWidget {
  const _NetworkHeader({
    required this.hasLive,
    required this.hasPlayback,
    required this.clusterCount,
    required this.nodes,
    required this.selectedNodeId,
    required this.onNodeSelected,
  });

  final bool hasLive;
  final bool hasPlayback;
  final int clusterCount;
  final List<CanvasNode> nodes;
  final String? selectedNodeId;
  final ValueChanged<CanvasNode?> onNodeSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final (label, color) = switch ((hasLive, hasPlayback)) {
      (true, _) => ('Live training', tokens.healthyColor),
      (false, true) => ('Review playback', tokens.studioPalette.accent),
      _ => ('Idle', AppTheme.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Zeta.of(context).textStyles.labelSmall.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              if (clusterCount > 0)
                Text(
                  '$clusterCount co-active ${clusterCount == 1 ? 'group' : 'groups'}',
                  style: Zeta.of(context).textStyles.bodyXSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              const Spacer(),
              const NetworkViewToggleButton(),
            ],
          ),
          const SizedBox(height: 8),
          NetworkLayerSearch(
            nodes: nodes,
            selectedNodeId: selectedNodeId,
            onSelected: onNodeSelected,
          ),
        ],
      ),
    );
  }
}

/// Toggles between [StudioViewMode.network] and [StudioViewMode.canvas].
///
/// Shared by the network view header, the architecture canvas chrome, and the
/// Run step so every entry point writes the same `studioViewModeProvider`
/// slot.
class NetworkViewToggleButton extends ConsumerWidget {
  const NetworkViewToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(studioViewModeProvider).viewMode;
    final isNetwork = mode == StudioViewMode.network;
    final tokens = NmtkShellTokens.of(context);
    return IconButton(
      tooltip: isNetwork ? 'Architecture canvas' : 'Network view',
      visualDensity: VisualDensity.compact,
      onPressed: () => ref
          .read(studioViewModeProvider.notifier)
          .setMode(isNetwork ? StudioViewMode.canvas : StudioViewMode.network),
      icon: Icon(
        // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (network graph hub)
        Icons.hub_outlined,
        size: 20,
        color: isNetwork ? tokens.studioPalette.accent : AppTheme.textSecondary,
      ),
    );
  }
}
