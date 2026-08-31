import 'dart:math' as math;
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/models/network_graph.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns a display color for a node based on its subtype.
Color _nodeColor(NetworkNode node) {
  if (node.type != 'ensemble') {
    if (node.subtype == 'input_error') return AppTheme.nodeErrorInput;
    return AppTheme.nodeInput;
  }
  switch (node.subtype) {
    case 'motor':
      return AppTheme.nodeMotor;
    case 'interneuron':
      return AppTheme.nodeInterneuron;
    case 'sensory':
      return AppTheme.nodeEnsemble;
    default:
      return AppTheme.nodeGenericEnsemble;
  }
}

/// Radius scaled by neuron count (ensembles only).
double _ensembleRadius(NetworkNode node) {
  if (node.type != 'ensemble') return 22.0;
  final n = (node.params['n_neurons'] as num?)?.toInt() ?? 50;
  // Scale from 20px (n≤20) to 38px (n≥200)
  const minR = 20.0;
  const maxR = 38.0;
  const minN = 20.0;
  const maxN = 200.0;
  final clamped = n.clamp(minN.toInt(), maxN.toInt()).toDouble();
  return minR + (maxR - minR) * ((clamped - minN) / (maxN - minN));
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Interactive network graph view drawn with CustomPainter.
class NetworkGraphView extends ConsumerStatefulWidget {
  const NetworkGraphView({super.key});

  @override
  ConsumerState<NetworkGraphView> createState() => _NetworkGraphViewState();
}

class _NetworkGraphViewState extends ConsumerState<NetworkGraphView> {
  static const double _layoutPadding = 48;

  final Map<String, Offset> _positions = {};
  String? _selectedId; // selected node OR edge id
  String? _draggingNode;
  NetworkGraph? _lastGraph;
  Size? _lastViewportSize;

  @override
  Widget build(BuildContext context) {
    final pipeline = ref.watch(pipelineProvider);
    final graph = pipeline.generateResult?.network;

    if (graph != _lastGraph) {
      _lastGraph = graph;
      _lastViewportSize = null;
      _positions.clear();
      _selectedId = null;
      _draggingNode = null;
    }

    if (graph == null || graph.nodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              size: 48,
              color: AppTheme.textSecondary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            const Text(
              'Run the model to inspect the compiled graph.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final showCondensedPreview = _shouldCondenseGraph(graph);

    // Resolve which item is selected (node or edge)
    NetworkNode? selectedNode;
    try {
      selectedNode = graph.nodes.firstWhere((n) => n.id == _selectedId);
    } on StateError {
      selectedNode = null;
    }

    NetworkEdge? selectedEdge;
    if (selectedNode == null) {
      try {
        selectedEdge = graph.edges.firstWhere((e) => e.id == _selectedId);
      } on StateError {
        selectedEdge = null;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactBanner =
            constraints.maxWidth < 480 || constraints.maxHeight < 420;
        final detailsPanelMaxHeight = math.min(
          220.0,
          constraints.maxHeight * 0.28,
        );
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: _buildPurposeBanner(
                showCondensedPreview,
                compact: compactBanner,
              ),
            ),
            Expanded(
              child: showCondensedPreview
                  ? _buildCondensedPreview(graph)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        _ensurePositions(graph, constraints);
                        return Container(
                          margin: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusMd),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusMd),
                                  child: GestureDetector(
                                    onPanStart: (d) => _onPanStart(d, graph),
                                    onPanUpdate: _onPanUpdate,
                                    onPanEnd: (_) =>
                                        setState(() => _draggingNode = null),
                                    onTapUp: (d) => _onTap(d, graph),
                                    child: CustomPaint(
                                      size: Size(
                                        constraints.maxWidth - 24,
                                        constraints.maxHeight - 24,
                                      ),
                                      painter: _NetworkPainter(
                                        graph: graph,
                                        positions: _positions,
                                        selectedId: _selectedId,
                                        radiusSm: NmtkShellTokens.of(context).radiusSm,
                                        radiusMd: NmtkShellTokens.of(context).radiusMd,
                                        selectedBorderColor: Zeta.of(context).colors.mainInverse,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // ── stat chips ──────────────────────────────────────
                              Positioned(
                                top: 12,
                                left: 12,
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _statChip(
                                      Icons
                                          .hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                                      '${graph.nodes.length} nodes',
                                    ),
                                    _statChip(
                                      ZetaIcons.arrow_forward,
                                      '${graph.edges.length} edges',
                                    ),
                                  ],
                                ),
                              ),
                              // ── legend ──────────────────────────────────────────
                              Positioned(
                                right: 12,
                                bottom: 12,
                                child: _buildLegend(),
                              ),
                              if (selectedNode != null)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: _buildScrollableInfoPanel(
                                    _buildNodePanel(selectedNode),
                                    maxHeight: detailsPanelMaxHeight,
                                  ),
                                ),
                              if (selectedNode == null && selectedEdge != null)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: _buildScrollableInfoPanel(
                                    _buildEdgePanel(selectedEdge, graph),
                                    maxHeight: detailsPanelMaxHeight,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  bool _shouldCondenseGraph(NetworkGraph graph) {
    if (graph.nodes.length < 2 || graph.edges.isEmpty) {
      return false;
    }

    final incoming = <String, int>{for (final node in graph.nodes) node.id: 0};
    final outgoing = <String, int>{for (final node in graph.nodes) node.id: 0};

    for (final edge in graph.edges) {
      incoming.update(edge.target, (count) => count + 1, ifAbsent: () => 1);
      outgoing.update(edge.source, (count) => count + 1, ifAbsent: () => 1);
    }

    final hasBranching =
        incoming.values.any((count) => count > 1) ||
        outgoing.values.any((count) => count > 1);
    if (hasBranching) {
      return false;
    }

    return graph.edges.length <= graph.nodes.length - 1;
  }

  // ── Layout ───────────────────────────────────────────────────────────────

  void _ensurePositions(NetworkGraph graph, BoxConstraints constraints) {
    final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
    final viewportChanged =
        _lastViewportSize == null ||
        (viewportSize.width - _lastViewportSize!.width).abs() > 0.5 ||
        (viewportSize.height - _lastViewportSize!.height).abs() > 0.5;
    final hasAll =
        _positions.length == graph.nodes.length &&
        graph.nodes.every((n) => _positions.containsKey(n.id));
    if (!viewportChanged && hasAll) return;
    _lastViewportSize = viewportSize;
    _positions
      ..clear()
      ..addAll(_computeTieredLayout(graph, viewportSize));
  }

  /// Left-to-right signal-flow layout.
  ///
  /// Tier 0 = input nodes, then BFS through edges to assign deeper tiers.
  Map<String, Offset> _computeTieredLayout(NetworkGraph graph, Size vp) {
    // Build adjacency: source → list of targets
    final adj = <String, List<String>>{};
    for (final e in graph.edges) {
      adj.putIfAbsent(e.source, () => []).add(e.target);
    }

    // Assign tiers via BFS starting from input nodes (or all nodes if none)
    final tier = <String, int>{};
    final queue = <String>[];

    for (final n in graph.nodes) {
      if (n.type == 'input_node') {
        tier[n.id] = 0;
        queue.add(n.id);
      }
    }
    // Fallback: if no inputs, seed all unvisited nodes at tier 0
    if (queue.isEmpty) {
      for (final n in graph.nodes) {
        tier[n.id] = 0;
        queue.add(n.id);
      }
    }

    int qi = 0;
    while (qi < queue.length) {
      final current = queue[qi++];
      final currentTier = tier[current]!;
      for (final next in (adj[current] ?? const <String>[])) {
        if (!tier.containsKey(next) || tier[next]! < currentTier + 1) {
          tier[next] = currentTier + 1;
          queue.add(next);
        }
      }
    }
    // Any node not reached gets tier 0
    for (final n in graph.nodes) {
      tier.putIfAbsent(n.id, () => 0);
    }

    // Group by tier
    final byTier = <int, List<String>>{};
    for (final n in graph.nodes) {
      final t = tier[n.id]!;
      byTier.putIfAbsent(t, () => []).add(n.id);
    }
    final maxTier = byTier.keys.reduce(math.max);
    final numTiers = maxTier + 1;

    final availW = vp.width - _layoutPadding * 2;
    final availH = vp.height - _layoutPadding * 2;
    final tierSpacing = numTiers <= 1 ? 0.0 : availW / (numTiers - 1);

    final positions = <String, Offset>{};
    for (final entry in byTier.entries) {
      final t = entry.key;
      final ids = entry.value;
      final count = ids.length;
      final x = _layoutPadding + (numTiers <= 1 ? availW / 2 : t * tierSpacing);
      for (var i = 0; i < count; i++) {
        final y =
            _layoutPadding +
            (count <= 1 ? availH / 2 : i * availH / (count - 1));
        positions[ids[i]] = Offset(x, y);
      }
    }
    return positions;
  }

  // ── Interaction ──────────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails details, NetworkGraph graph) {
    for (final node in graph.nodes) {
      final pos = _positions[node.id];
      if (pos != null && (pos - details.localPosition).distance < 36) {
        setState(() => _draggingNode = node.id);
        break;
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_draggingNode != null) {
      setState(() {
        _positions[_draggingNode!] =
            _positions[_draggingNode!]! + details.delta;
      });
    }
  }

  void _onTap(TapUpDetails details, NetworkGraph graph) {
    // Check nodes first
    for (final node in graph.nodes) {
      final pos = _positions[node.id];
      if (pos != null && (pos - details.localPosition).distance < 36) {
        final nodeId = node.id;
        setState(() => _selectedId = nodeId == _selectedId ? null : nodeId);
        return;
      }
    }
    // Check edges (tap near midpoint)
    for (final edge in graph.edges) {
      final from = _positions[edge.source];
      final to = _positions[edge.target];
      if (from == null || to == null) continue;
      final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
      if ((mid - details.localPosition).distance < 20) {
        final edgeId = edge.id;
        setState(() => _selectedId = edgeId == _selectedId ? null : edgeId);
        return;
      }
    }
    setState(() => _selectedId = null);
  }

  // ── UI helpers ───────────────────────────────────────────────────────────

  Widget _buildPurposeBanner(
    bool showCondensedPreview, {
    required bool compact,
  }) {
    return SizedBox(
      height: compact ? 52 : 68,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 10 : 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusMd),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              showCondensedPreview
                  ? Icons.route_outlined
                  : Icons
                        .hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              size: compact ? 16 : 18,
              color: AppTheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                compact
                    ? (showCondensedPreview
                          ? 'Execution preview only. Studio is showing counts instead of a repetitive straight-through graph. Use NeuroSim for topology inspection.'
                          : 'Execution preview only. Studio normalizes this graph; use NeuroSim for detailed topology inspection.')
                    : (showCondensedPreview
                          ? 'Execution preview only: this generated network is a straight-through handoff, so Studio shows the key counts instead of a repetitive graph. Use NeuroSim when you need a fuller topology view.'
                          : 'Execution preview only: this graph is a normalized sanity check for the generated network, not a layout editor. Similar specs will often look alike here; use NeuroSim for detailed topology inspection.'),
                maxLines: compact ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: compact ? 11 : 12,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCondensedPreview(NetworkGraph graph) {
    final ensembleCount = graph.nodes
        .where((node) => node.type == 'ensemble')
        .length;
    final inputCount = graph.nodes.length - ensembleCount;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Straight-through generated flow',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This output does not branch, so the visual graph adds little beyond the generated counts below. Use the editor number picker to adjust values, then rerun Generate when you need an updated artifact preview.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statChip(
                Icons.hub_outlined,
                '${graph.nodes.length} nodes',
              ), // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              _statChip(ZetaIcons.arrow_forward, '${graph.edges.length} edges'),
              _statChip(
                ZetaIcons.radio_button_unchecked,
                '$ensembleCount ensembles',
              ),
              _statChip(
                Icons.input_outlined,
                '$inputCount inputs',
              ), // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScrollableInfoPanel(Widget child, {required double maxHeight}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(padding: EdgeInsets.zero, child: child),
    );
  }

  Widget _statChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusChip),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    final items = [
      ('Sensory', AppTheme.nodeEnsemble),
      ('Motor', AppTheme.nodeMotor),
      ('Interneuron', AppTheme.nodeInterneuron),
      ('Input', AppTheme.nodeInput),
      ('Error', AppTheme.nodeErrorInput),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(
          NmtkShellTokens.of(context).radiusSm,
        ),
        border: Border.all(color: AppTheme.border),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: items
            .map(
              (item) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LegendDot(color: item.$2),
                  const SizedBox(width: 5),
                  Text(
                    item.$1,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildNodePanel(NetworkNode node) {
    final Color color = _nodeColor(node);
    final String subtype = node.subtype;
    final paramRows = <_ParamRow>[];

    if (node.type == 'ensemble') {
      final n = node.params['n_neurons'];
      final dims = node.params['dimensions'];
      final tauRc = node.params['tau_rc'];
      final tauRef = node.params['tau_ref'];
      final nType = node.params['neuron_type'];
      if (n != null) paramRows.add(_ParamRow('Neurons', n.toString()));
      if (dims != null) paramRows.add(_ParamRow('Dimensions', dims.toString()));
      if (tauRc != null) {
        paramRows.add(
          _ParamRow(
            'τ_rc',
            '${(tauRc as num).toDouble().toStringAsFixed(4)} s',
          ),
        );
      }
      if (tauRef != null) {
        paramRows.add(
          _ParamRow(
            'τ_ref',
            '${(tauRef as num).toDouble().toStringAsFixed(4)} s',
          ),
        );
      }
      if (nType != null) {
        paramRows.add(_ParamRow('Neuron type', nType.toString()));
      }
    }

    return _InfoPanel(
      icon: node.type == 'ensemble'
          ? ZetaIcons.radio_button_unchecked
          : ZetaIcons.stop,
      color: color,
      title: node.label,
      badge: subtype,
      rows: paramRows,
    );
  }

  Widget _buildEdgePanel(NetworkEdge edge, NetworkGraph _) {
    final bool isInhibitory = edge.isInhibitory;
    final bool hasLearning = edge.hasLearningRule;
    final Color color = hasLearning
        ? AppTheme.edgePlastic
        : isInhibitory
        ? AppTheme.edgeInhibitory
        : AppTheme.edgeExcitatory;

    final num? weight = edge.params['transform'] as num?;
    final num? synapse = edge.params['synapse'] as num?;
    final String? rule = edge.learningRule;

    final rows = <_ParamRow>[
      _ParamRow('From', edge.source),
      _ParamRow('To', edge.target),
      if (weight != null)
        _ParamRow('Weight', weight.toDouble().toStringAsFixed(3)),
      if (synapse != null)
        _ParamRow(
          'Synapse τ',
          '${(synapse.toDouble() * 1000).toStringAsFixed(1)} ms',
        ),
      _ParamRow(
        'Type',
        hasLearning
            ? 'Plastic ($rule)'
            : isInhibitory
            ? 'Inhibitory'
            : 'Excitatory',
      ),
    ];

    return _InfoPanel(
      icon: ZetaIcons.arrow_forward,
      color: color,
      title: '${edge.source} → ${edge.target}',
      badge: hasLearning
          ? 'plastic'
          : isInhibitory
          ? 'inhibitory'
          : 'excitatory',
      rows: rows,
    );
  }
}

// ---------------------------------------------------------------------------
// Info panel widget
// ---------------------------------------------------------------------------

class _ParamRow {
  final String key;
  final String value;
  const _ParamRow(this.key, this.value);
}

class _InfoPanel extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String badge;
  final List<_ParamRow> rows;

  const _InfoPanel({
    required this.icon,
    required this.color,
    required this.title,
    required this.badge,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: rows
                  .map(
                    (r) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${r.key}: ',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            TextSpan(
                              text: r.value,
                              style: const TextStyle(
                                color: AppTheme.synNumber,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CustomPainter
// ---------------------------------------------------------------------------

class _NetworkPainter extends CustomPainter {
  final NetworkGraph graph;
  final Map<String, Offset> positions;
  final String? selectedId;
  final double radiusSm;
  final double radiusMd;
  final Color selectedBorderColor;

  _NetworkPainter({
    required this.graph,
    required this.positions,
    this.selectedId,
    required this.radiusSm,
    required this.radiusMd,
    required this.selectedBorderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);
    _paintEdges(canvas);
    _paintNodes(canvas);
  }

  // ── Background ───────────────────────────────────────────────────────────

  void _paintBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.surface, AppTheme.surfaceVariant],
        ).createShader(rect),
    );

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    const spacing = 32.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    canvas.drawRect(
      rect.deflate(0.5),
      Paint()
        ..color = AppTheme.border.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  // ── Edges ────────────────────────────────────────────────────────────────

  void _paintEdges(Canvas canvas) {
    for (final edge in graph.edges) {
      final from = positions[edge.source];
      final to = positions[edge.target];
      if (from == null || to == null) continue;

      final isSelected = edge.id == selectedId;

      // Determine visual properties from the typed edge fields
      final isInhibitory =
          edge.isInhibitory || ((_edgeNum(edge, 'transform') ?? 0) < 0);
      final hasLearning = edge.hasLearningRule;
      final hasDelay = edge.hasDelay;
      final weight = _edgeNum(edge, 'transform') ?? 1.0;
      final learningRule = edge.learningRule;
      final synapseTau = _edgeNum(edge, 'synapse');

      final Color edgeColor = hasLearning
          ? AppTheme.edgePlastic
          : isInhibitory
          ? AppTheme.edgeInhibitory
          : AppTheme.edgeExcitatory;

      final strokeWidth =
          (isSelected ? 3.0 : 1.5) + math.min(2.5, weight.abs() * 0.8);

      final paint = Paint()
        ..color = isSelected ? edgeColor : edgeColor.withValues(alpha: 0.75)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke;

      // Draw line: dashed for delay, dotted for plastic, solid otherwise
      if (hasDelay || hasLearning) {
        _drawDashedLine(
          canvas,
          from,
          to,
          paint,
          dashLen: hasLearning ? 4.0 : 8.0,
          gapLen: hasLearning ? 3.0 : 5.0,
        );
      } else {
        canvas.drawLine(from, to, paint);
      }

      _drawArrowhead(canvas, from, to, paint, edgeColor);

      // Edge label — richer content
      final labelParts = <String>[];
      labelParts.add('w=${weight.toStringAsFixed(1)}');
      if (synapseTau != null) {
        labelParts.add('τ=${(synapseTau * 1000).toStringAsFixed(1)}ms');
      }
      if (hasLearning && learningRule != null) {
        labelParts.add(learningRule);
      }
      _drawEdgeLabel(
        canvas,
        from,
        to,
        labelParts.join(' | '),
        edgeColor,
        isSelected: isSelected,
      );
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint, {
    double dashLen = 8.0,
    double gapLen = 5.0,
  }) {
    final dir = to - from;
    final total = dir.distance;
    if (total < 1) return;
    final unit = dir / total;
    double drawn = 0;
    bool drawing = true;
    while (drawn < total) {
      final segLen = drawing ? dashLen : gapLen;
      final end = math.min(drawn + segLen, total);
      if (drawing) {
        canvas.drawLine(from + unit * drawn, from + unit * end, paint);
      }
      drawn = end;
      drawing = !drawing;
    }
  }

  void _drawArrowhead(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint,
    Color color,
  ) {
    final dir = to - from;
    final len = dir.distance;
    if (len < 1) return;
    final unit = dir / len;

    // Source node radius (for tip offset)
    NetworkNode? toNode;
    try {
      toNode = graph.nodes.firstWhere((n) => n.id == _idForPos(to));
    } on StateError {
      toNode = null;
    }
    final tipOffset = toNode != null ? _ensembleRadius(toNode) + 2 : 30.0;
    final tip = to - unit * tipOffset;

    const arrowLen = 10.0;
    const arrowAngle = 0.4;
    final left =
        tip -
        Offset(
          unit.dx * arrowLen - unit.dy * arrowLen * math.tan(arrowAngle),
          unit.dy * arrowLen + unit.dx * arrowLen * math.tan(arrowAngle),
        );
    final right =
        tip -
        Offset(
          unit.dx * arrowLen + unit.dy * arrowLen * math.tan(arrowAngle),
          unit.dy * arrowLen - unit.dx * arrowLen * math.tan(arrowAngle),
        );

    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close(),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  void _drawEdgeLabel(
    Canvas canvas,
    Offset from,
    Offset to,
    String text,
    Color edgeColor, {
    required bool isSelected,
  }) {
    final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: isSelected ? edgeColor : AppTheme.textSecondary,
          fontSize: 9,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final offset = mid - Offset(tp.width / 2, tp.height + 4);
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(offset.dx - 4, offset.dy - 2, tp.width + 8, tp.height + 4),
      Radius.circular(radiusSm),
    );
    canvas.drawRRect(
      bgRect,
      Paint()..color = AppTheme.background.withValues(alpha: 0.88),
    );
    tp.paint(canvas, offset);
  }

  // ── Nodes ────────────────────────────────────────────────────────────────

  void _paintNodes(Canvas canvas) {
    for (final node in graph.nodes) {
      final pos = positions[node.id];
      if (pos == null) continue;

      final isSelected = node.id == selectedId;
      final color = _nodeColor(node);
      final radius = _ensembleRadius(node);
      final isEnsemble = node.type == 'ensemble';

      // Glow
      if (isEnsemble) {
        canvas.drawCircle(
          pos,
          radius + 10,
          Paint()..color = color.withValues(alpha: 0.12),
        );
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: pos,
              width: radius * 2.2 + 14,
              height: radius * 2.2 + 14,
            ),
            Radius.circular(radiusMd),
          ),
          Paint()..color = color.withValues(alpha: 0.10),
        );
      }

      // Selection ring
      if (isSelected) {
        if (isEnsemble) {
          canvas.drawCircle(
            pos,
            radius + 6,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.25)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        } else {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: pos,
                width: radius * 2.2 + 12,
                height: radius * 2.2 + 12,
              ),
              Radius.circular(radiusMd),
            ),
            Paint()
              ..color = Colors.white.withValues(alpha: 0.25)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
      }

      // Shadow
      final shadowPaint = Paint()..color = Colors.black.withValues(alpha: 0.28);
      final fillPaint = Paint()..color = color.withValues(alpha: 0.30);
      final borderPaint = Paint()
        ..color = isSelected ? selectedBorderColor : color
        ..strokeWidth = isSelected ? 3.0 : 2.2
        ..style = PaintingStyle.stroke;

      if (isEnsemble) {
        canvas.drawCircle(pos + const Offset(2, 2), radius, shadowPaint);
        canvas.drawCircle(pos, radius, fillPaint);
        canvas.drawCircle(pos, radius, borderPaint);
      } else {
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: pos,
            width: radius * 2.2,
            height: radius * 2.2,
          ),
          Radius.circular(radiusMd),
        );
        canvas.drawRRect(rect.shift(const Offset(2, 2)), shadowPaint);
        canvas.drawRRect(rect, fillPaint);
        canvas.drawRRect(rect, borderPaint);
      }

      // Center dot
      canvas.drawCircle(
        pos,
        4,
        Paint()..color = Colors.white.withValues(alpha: 0.95),
      );

      // Label line 1: node name
      _drawNodeLabel(canvas, node, pos, radius, color);
    }
  }

  void _drawNodeLabel(
    Canvas canvas,
    NetworkNode node,
    Offset pos,
    double radius,
    Color color,
  ) {
    final String nodeLabel = node.label;

    // Primary label
    final tp1 = TextPainter(
      text: TextSpan(
        text: nodeLabel,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Secondary label (params) — only for ensembles
    TextPainter? tp2;
    if (node.type == 'ensemble') {
      final n = node.params['n_neurons'];
      final tauRc = node.params['tau_rc'];
      final parts = <String>[];
      if (n != null) parts.add('n=$n');
      if (tauRc != null) {
        parts.add('τ=${(tauRc as num).toDouble().toStringAsFixed(3)}s');
      }
      if (parts.isNotEmpty) {
        tp2 = TextPainter(
          text: TextSpan(
            text: parts.join('  '),
            style: TextStyle(
              color: color.withValues(alpha: 0.85),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
      }
    }

    final totalH = tp1.height + (tp2 != null ? tp2.height + 2 : 0);
    final bgW = math.max(tp1.width, tp2?.width ?? 0) + 12;
    final bgTop = pos.dy + radius + 6;

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pos.dx - bgW / 2, bgTop - 3, bgW, totalH + 6),
      Radius.circular(radiusSm),
    );
    canvas.drawRRect(
      bgRect,
      Paint()..color = AppTheme.background.withValues(alpha: 0.88),
    );

    tp1.paint(canvas, Offset(pos.dx - tp1.width / 2, bgTop));
    if (tp2 != null) {
      tp2.paint(canvas, Offset(pos.dx - tp2.width / 2, bgTop + tp1.height + 2));
    }
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  /// Look up which node id is at position [pos] in the positions map.
  String _idForPos(Offset pos) {
    for (final entry in positions.entries) {
      if ((entry.value - pos).distance < 1) return entry.key;
    }
    return '';
  }

  double? _edgeNum(NetworkEdge edge, String key) {
    final v = edge.params[key];
    if (v is num) return v.toDouble();
    return null;
  }

  @override
  bool shouldRepaint(covariant _NetworkPainter old) =>
      old.graph != graph ||
      old.positions != positions ||
      old.selectedId != selectedId ||
      old.radiusSm != radiusSm ||
      old.radiusMd != radiusMd ||
      old.selectedBorderColor != selectedBorderColor;
}

// ---------------------------------------------------------------------------
// Legend dot
// ---------------------------------------------------------------------------

class _LegendDot extends StatelessWidget {
  final Color color;
  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
