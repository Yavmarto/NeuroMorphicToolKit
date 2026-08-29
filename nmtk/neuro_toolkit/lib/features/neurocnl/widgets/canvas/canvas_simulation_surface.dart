import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/bulk_spike_frame.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/preview.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/simulation_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/animated_snn_playback.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/network_canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/time_series_chart.dart';

class CanvasSimulationSurface extends ConsumerWidget {
  const CanvasSimulationSurface({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final simState = ref.watch(simulationProvider);

    final playback = simState.playback;
    final selectedNodeId = simState.selectedNodeId;
    final selectedNode = selectedNodeId == null
        ? null
        : playback?.nodeById(selectedNodeId);
    final bulkFrame = playback?.bulkSpikeFrame;

    return ColoredBox(
      color: Zeta.of(context).colors.surfacePrimary,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Zeta.of(context).colors.surfacePrimary,
                border: Border.all(color: Zeta.of(context).colors.borderSubtle),
              ),
              child: const NetworkCanvas(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Zeta.of(context).colors.surfacePrimary,
                border: Border.all(color: Zeta.of(context).colors.borderSubtle),
              ),
              child: playback == null
                  ? const _SimulationEmptyState()
                  : bulkFrame != null
                  ? _BulkNodeVisualizationPanel(
                      bulkFrame: bulkFrame,
                      graphNodes: simState.graphNodes,
                      currentTimeMs: simState.currentTime,
                    )
                  : _SimulationDetailsPanel(
                      playback: playback,
                      selectedNode: selectedNode,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BulkNodeVisualizationPanel extends StatefulWidget {
  const _BulkNodeVisualizationPanel({
    required this.bulkFrame,
    required this.graphNodes,
    required this.currentTimeMs,
  });

  final BulkSpikeFrame bulkFrame;
  final List<CanvasNode> graphNodes;
  final double currentTimeMs;

  @override
  State<_BulkNodeVisualizationPanel> createState() =>
      _BulkNodeVisualizationPanelState();
}

class _BulkNodeVisualizationPanelState
    extends State<_BulkNodeVisualizationPanel> {
  final Map<String, NeuronRenderer> _renderers = {};

  @override
  void initState() {
    super.initState();
    _syncFrames();
  }

  @override
  void didUpdateWidget(_BulkNodeVisualizationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFrames();
  }

  void _syncFrames() {
    for (final entry in widget.bulkFrame.nodes.entries) {
      final renderer = _renderers.putIfAbsent(entry.key, createNeuronRenderer);
      renderer.pushFrame(
        entry.value.toVisualizationFrame(
          simulationTimeMs: widget.currentTimeMs,
          scaleOverride: widget.bulkFrame.scale,
        ),
      );
    }
    // Drop renderers for nodes no longer present in this frame.
    final stale = _renderers.keys
        .where((id) => !widget.bulkFrame.nodes.containsKey(id))
        .toList();
    for (final id in stale) {
      _renderers.remove(id)?.dispose();
    }
  }

  @override
  void dispose() {
    for (final renderer in _renderers.values) {
      renderer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only render boxes for nodes that both have real canvas geometry and
    // emitted spikes in this bulk frame — nodes with no entry in
    // bulkFrame.nodes contributed zero spikes this tick.
    final activeNodes = widget.graphNodes
        .where((node) => widget.bulkFrame.nodes.containsKey(node.id))
        .toList();

    if (activeNodes.isEmpty) {
      return const Center(child: Text('No active nodes in this frame.'));
    }

    final minX = activeNodes.map((n) => n.position[0]).reduce(math.min);
    final minY = activeNodes.map((n) => n.position[1]).reduce(math.min);

    return Stack(
      children: activeNodes.map((node) {
        final renderer = _renderers[node.id]!;
        renderer.attach(Size(node.width, node.height));
        return Positioned(
          left: node.position[0] - minX,
          top: node.position[1] - minY,
          width: node.width,
          height: node.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Zeta.of(context).colors.borderSubtle),
            ),
            child: Column(
              children: [
                Text(
                  resolveNodeDisplayName(node),
                  style: Zeta.of(context).textStyles.labelSmall,
                ),
                Expanded(child: renderer.buildSurface(context)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SimulationEmptyState extends StatelessWidget {
  const _SimulationEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons
                  .insights_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              size: 36,
              color: Zeta.of(context).colors.mainPrimary,
            ),
            const SizedBox(height: 16),
            Text(
              'Run a preview to inspect spike propagation, raster activity, and membrane traces for this canvas.',
              textAlign: TextAlign.center,
              style: Zeta.of(context).textStyles.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _SimulationDetailsPanel extends ConsumerWidget {
  const _SimulationDetailsPanel({
    required this.playback,
    required this.selectedNode,
  });

  final PreviewPlayback playback;
  final PreviewNodePlayback? selectedNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final simState = ref.watch(simulationProvider);
    final notifier = ref.read(simulationProvider.notifier);
    final graphNodesById = <String, CanvasNode>{
      for (final graphNode in simState.graphNodes) graphNode.id: graphNode,
    };
    String displayNameForNodeId(String nodeId) {
      final graphNode = graphNodesById[nodeId];
      return graphNode == null ? nodeId : resolveNodeDisplayName(graphNode);
    }

    final selected = selectedNode ?? playback.nodes.first;
    final traces = selected.voltageTraces.values.toList();
    final maxTraceLen = traces.fold<int>(
      0,
      (maxLen, trace) => trace.length > maxLen ? trace.length : maxLen,
    );
    final time = maxTraceLen <= 1
        ? <double>[]
        : List<double>.generate(
            maxTraceLen,
            (index) => playback.durationMs * index / (maxTraceLen - 1),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Visual Simulation',
          style: Zeta.of(context).textStyles.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatChip(label: 'Nodes', value: '${playback.nodes.length}'),
            _StatChip(
              label: 'Spikes',
              value: '${playback.summary.totalSpikes}',
            ),
            _StatChip(
              label: 'Edges',
              value: '${playback.summary.edgeEventCount}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: selected.nodeId,
          decoration: const InputDecoration(
            labelText: 'Selected population',
            border: OutlineInputBorder(),
          ),
          items: playback.nodes
              .map(
                (node) => DropdownMenuItem<String>(
                  value: node.nodeId,
                  child: Text(displayNameForNodeId(node.nodeId)),
                ),
              )
              .toList(),
          onChanged: notifier.selectNode,
        ),
        const SizedBox(height: 16),
        Text(
          '${simState.currentTime.toStringAsFixed(1)} / ${playback.durationMs.toStringAsFixed(1)} ms',
          style: Zeta.of(context).textStyles.bodySmall,
        ),
        Slider(
          value: simState.currentTime.clamp(0.0, playback.durationMs),
          min: 0.0,
          max: playback.durationMs <= 0 ? 1.0 : playback.durationMs,
          onChanged: notifier.setCurrentTime,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Column(
            children: [
              Expanded(
                flex: 5,
                child: _AnimatedRasterPanel(
                  spikes: selected.spikeTrains.values.toList(),
                  durationMs: playback.durationMs,
                  currentTimeMs: simState.currentTime,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                flex: 5,
                child: _AnimatedTracePanel(
                  traces: traces,
                  time: time,
                  durationMs: playback.durationMs,
                  currentTimeMs: simState.currentTime,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnimatedRasterPanel extends StatelessWidget {
  const _AnimatedRasterPanel({
    required this.spikes,
    required this.durationMs,
    required this.currentTimeMs,
  });

  final List<List<double>> spikes;
  final double durationMs;
  final double currentTimeMs;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Zeta.of(context).colors.surfacePrimary,
        border: Border.all(color: Zeta.of(context).colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Spike Raster',
              style: Zeta.of(context).textStyles.labelLarge,
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: AnimatedRasterPainter(
                  spikes: spikes,
                  duration: durationMs,
                  currentTimeMs: currentTimeMs,
                  visibleRange: (start: 0.0, end: durationMs),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedTracePanel extends StatelessWidget {
  const _AnimatedTracePanel({
    required this.traces,
    required this.time,
    required this.durationMs,
    required this.currentTimeMs,
  });

  final List<List<double>> traces;
  final List<double> time;
  final double durationMs;
  final double currentTimeMs;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Zeta.of(context).colors.surfacePrimary,
        border: Border.all(color: Zeta.of(context).colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Membrane Traces',
              style: Zeta.of(context).textStyles.labelLarge,
            ),
          ),
          Expanded(
            child: traces.isEmpty || time.isEmpty
                ? const Center(child: Text('No membrane traces recorded.'))
                : LayoutBuilder(
                    builder: (context, constraints) => CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: AnimatedChartPainter(
                        traces: traces,
                        time: time,
                        colors: traceColorPalette(context),
                        currentTimeMs: currentTimeMs,
                        duration: durationMs,
                        visibleRange: (start: 0.0, end: durationMs),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Zeta.of(context).colors.surfacePrimary,
        border: Border.all(color: Zeta.of(context).colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          '$label: $value',
          style: Zeta.of(context).textStyles.bodySmall,
        ),
      ),
    );
  }
}
