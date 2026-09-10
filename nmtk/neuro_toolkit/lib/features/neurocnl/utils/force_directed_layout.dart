import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';

/// Tunable parameters for [ForceDirectedLayout].
///
/// The defaults are tuned for the network view's intended granularity —
/// components/layers (tens of nodes), not raw neurons. The force model is the
/// classic Fruchterman-Reingold style relaxation:
///
/// * **repulsion** — every pair of nodes pushes apart with an inverse-square
///   force, so unrelated layers spread out;
/// * **edge-spring** — connected nodes pull toward [springLength], so wired
///   layers cluster;
/// * **centering** — a weak pull toward the origin keeps the whole graph from
///   drifting off-canvas.
class ForceDirectedLayoutConfig {
  const ForceDirectedLayoutConfig({
    this.repulsion = 9000.0,
    this.minSeparation = 36.0,
    this.springLength = 60.0,
    this.springStrength = 0.16,
    this.centeringStrength = 0.008,
    this.damping = 0.85,
    this.maxVelocity = 46.0,
    this.seedSpacing = 44.0,
    this.depthJitter = 0.35,
    this.settleEpsilon = 0.4,
    this.maxIterations = 400,
  });

  /// Coulomb constant for the inverse-square pairwise repulsion.
  final double repulsion;

  /// Floor on the pairwise distance used by repulsion, so two coincident nodes
  /// do not produce an unbounded force. Also acts as the target minimum gap.
  final double minSeparation;

  /// Rest length of an edge spring. Connected nodes settle near this distance.
  final double springLength;

  /// Hookean spring constant (force per unit of stretch).
  final double springStrength;

  /// Strength of the weak pull toward the layout origin.
  final double centeringStrength;

  /// Velocity retained each step. Below 1.0 the system loses energy and settles.
  final double damping;

  /// Per-step speed cap, so a bad topology cannot fling a node to infinity.
  final double maxVelocity;

  /// Radius of the first ring of the deterministic seed spiral.
  final double seedSpacing;

  /// How far a node's [ForceDirectedLayout.depths] may deviate from its
  /// topology tier, in `0..1`. A small jitter keeps nodes in the same tier from
  /// sitting on one perfectly flat plane, which would flatten the 2.5D look.
  final double depthJitter;

  /// Mean kinetic energy at or below which the layout is considered settled.
  final double settleEpsilon;

  /// Hard cap on relaxation steps, so a pathological graph cannot spin.
  final int maxIterations;

  ForceDirectedLayoutConfig copyWith({
    double? repulsion,
    double? minSeparation,
    double? springLength,
    double? springStrength,
    double? centeringStrength,
    double? damping,
    double? maxVelocity,
    double? seedSpacing,
    double? depthJitter,
    double? settleEpsilon,
    int? maxIterations,
  }) {
    return ForceDirectedLayoutConfig(
      repulsion: repulsion ?? this.repulsion,
      minSeparation: minSeparation ?? this.minSeparation,
      springLength: springLength ?? this.springLength,
      springStrength: springStrength ?? this.springStrength,
      centeringStrength: centeringStrength ?? this.centeringStrength,
      damping: damping ?? this.damping,
      maxVelocity: maxVelocity ?? this.maxVelocity,
      seedSpacing: seedSpacing ?? this.seedSpacing,
      depthJitter: depthJitter ?? this.depthJitter,
      settleEpsilon: settleEpsilon ?? this.settleEpsilon,
      maxIterations: maxIterations ?? this.maxIterations,
    );
  }
}

/// Client-side force-directed layout for a [CanvasGraph].
///
/// Positions live in an arbitrary origin-centred coordinate space; call
/// [fitToSize] to map them onto a concrete canvas. The engine is deliberately
/// pure Dart (no Flutter widgets, no randomness): the same graph always yields
/// the same layout, which keeps the view stable across rebuilds and makes the
/// engine directly unit-testable.
///
/// Use it in two ways:
///
/// * one-shot — `ForceDirectedLayout(graph).relax()` for a settled layout on a
///   topology change;
/// * incremental — call [step] once per animation frame (or on a throttle) to
///   keep relaxing live during training without re-seeding from scratch, which
///   would make the graph jump.
class ForceDirectedLayout {
  ForceDirectedLayout(
    CanvasGraph graph, {
    this.config = const ForceDirectedLayoutConfig(),
    bool useStoredPositions = false,
  }) {
    _graph = graph;
    _indexNodes();
    _seed(useStoredPositions: useStoredPositions);
    _depths = computeNetworkDepths(graph, jitter: config.depthJitter);
  }

  final ForceDirectedLayoutConfig config;

  late CanvasGraph _graph;

  final Map<String, Offset> _positions = <String, Offset>{};
  final Map<String, Offset> _velocities = <String, Offset>{};
  final Set<String> _pinned = <String>{};

  /// Adjacency built once per topology so [step] does not rebuild it per frame.
  final Map<String, List<String>> _adjacency = <String, List<String>>{};
  final Map<String, int> _incoming = <String, int>{};

  Map<String, double> _depths = const <String, double>{};

  int _iterations = 0;
  double _kineticEnergy = double.infinity;

  CanvasGraph get graph => _graph;

  /// Current positions keyed by node id. Unmodifiable — use [moveNode]/[pin] to
  /// change a node during interaction.
  Map<String, Offset> get positions =>
      Map<String, Offset>.unmodifiable(_positions);

  /// Simulated depth in `0..1` per node, `1` nearest the viewer and `0`
  /// farthest. Derived from topology (see [computeNetworkDepths]).
  Map<String, double> get depths => Map<String, double>.unmodifiable(_depths);

  /// Number of relaxation steps taken so far.
  int get iterations => _iterations;

  /// Mean kinetic energy from the most recent [step].
  double get kineticEnergy => _kineticEnergy;

  /// True once the layout has settled below
  /// [ForceDirectedLayoutConfig.settleEpsilon] or hit the iteration cap.
  bool get isSettled =>
      _kineticEnergy <= config.settleEpsilon ||
      _iterations >= config.maxIterations;

  /// Ids currently pinned (held in place by a user drag).
  Set<String> get pinnedNodeIds => Set<String>.unmodifiable(_pinned);

  // ── Seeding ────────────────────────────────────────────────────────────────

  void _indexNodes() {
    _adjacency.clear();
    _incoming.clear();
    for (final node in _graph.nodes) {
      _adjacency[node.id] = <String>[];
      _incoming[node.id] = 0;
    }
    for (final edge in _graph.edges) {
      if (!_adjacency.containsKey(edge.sourceNodeId) ||
          !_adjacency.containsKey(edge.targetNodeId)) {
        continue;
      }
      _adjacency[edge.sourceNodeId]!.add(edge.targetNodeId);
      _incoming.update(
        edge.targetNodeId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
  }

  /// Deterministic golden-angle spiral. No RNG, so tests and rebuilds are
  /// stable. When [useStoredPositions] is true a node's own `position` is used
  /// instead, which preserves a hand-arranged editor layout as the start point.
  void _seed({required bool useStoredPositions}) {
    _positions.clear();
    _velocities.clear();
    _pinned.clear();

    final nodes = _graph.nodes;
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (useStoredPositions && node.position.length >= 2) {
        _positions[node.id] = Offset(node.position[0], node.position[1]);
        continue;
      }
      final angle = i * _goldenAngle;
      final radius = config.seedSpacing * math.sqrt(i + 1);
      _positions[node.id] = Offset(
        radius * math.cos(angle),
        radius * math.sin(angle),
      );
      _velocities[node.id] = Offset.zero;
    }
  }

  static const double _goldenAngle = 2.399963229728653;

  // ── Relaxation ─────────────────────────────────────────────────────────────

  /// Relaxes the layout up to [iterations] steps (defaults to
  /// [ForceDirectedLayoutConfig.maxIterations]) or until settled. Returns the
  /// number of steps actually taken.
  int relax([int? iterations]) {
    final limit = iterations ?? config.maxIterations;
    var taken = 0;
    while (taken < limit && !isSettled) {
      step();
      taken++;
    }
    return taken;
  }

  /// Advances the simulation one step and returns the mean kinetic energy.
  double step() {
    final ids = _positions.keys.toList(growable: false);
    final count = ids.length;
    if (count == 0) {
      _kineticEnergy = 0;
      return 0;
    }

    final forces = <String, Offset>{for (final id in ids) id: Offset.zero};

    _applyRepulsion(ids, forces);
    _applySprings(forces);

    var energy = 0.0;
    for (final id in ids) {
      final position = _positions[id]!;
      final force = forces[id]! - position * config.centeringStrength;
      var velocity = (_velocities[id] ?? Offset.zero) + force;
      velocity = velocity * config.damping;
      final speed = velocity.distance;
      if (speed > config.maxVelocity) {
        velocity = velocity / speed * config.maxVelocity;
      }

      if (_pinned.contains(id)) {
        _velocities[id] = Offset.zero;
        continue;
      }

      _velocities[id] = velocity;
      _positions[id] = position + velocity;
      energy += velocity.distanceSquared;
    }

    _kineticEnergy = energy / count;
    _iterations++;
    return _kineticEnergy;
  }

  void _applyRepulsion(List<String> ids, Map<String, Offset> forces) {
    for (var i = 0; i < ids.length; i++) {
      final a = ids[i];
      final pa = _positions[a]!;
      for (var j = i + 1; j < ids.length; j++) {
        final b = ids[j];
        var delta = pa - _positions[b]!;
        var distance = delta.distance;
        if (distance < 0.001) {
          // Coincident nodes: nudge apart deterministically by id order.
          delta = i < j ? const Offset(0.5, 0.5) : const Offset(-0.5, -0.5);
          distance = delta.distance;
        }
        final direction = delta / distance;
        final separation = math.max(distance, config.minSeparation);
        final magnitude = config.repulsion / (separation * separation);
        final force = direction * magnitude;
        forces[a] = forces[a]! + force;
        forces[b] = forces[b]! - force;
      }
    }
  }

  void _applySprings(Map<String, Offset> forces) {
    for (final edge in _graph.edges) {
      final source = _positions[edge.sourceNodeId];
      final target = _positions[edge.targetNodeId];
      if (source == null ||
          target == null ||
          edge.sourceNodeId == edge.targetNodeId) {
        continue;
      }
      var delta = target - source;
      var distance = delta.distance;
      if (distance < 0.001) {
        delta = const Offset(0.5, 0.5);
        distance = delta.distance;
      }
      final direction = delta / distance;
      final magnitude =
          config.springStrength * (distance - config.springLength);
      final force = direction * magnitude;
      forces[edge.sourceNodeId] = forces[edge.sourceNodeId]! + force;
      forces[edge.targetNodeId] = forces[edge.targetNodeId]! - force;
    }
  }

  // ── Mutation ───────────────────────────────────────────────────────────────

  /// Replaces the graph while preserving the position, velocity, and pinned
  /// state of nodes that survive the change. New nodes are seeded on the spiral
  /// near the existing centroid. This is what keeps a live training view from
  /// jumping when a node is added or removed.
  void updateGraph(CanvasGraph graph) {
    final previousPositions = Map<String, Offset>.from(_positions);
    final previousVelocities = Map<String, Offset>.from(_velocities);
    final previousPinned = Set<String>.from(_pinned);

    _graph = graph;
    _indexNodes();
    _seed(useStoredPositions: false);
    _depths = computeNetworkDepths(graph, jitter: config.depthJitter);

    for (final node in graph.nodes) {
      final previous = previousPositions[node.id];
      if (previous != null) {
        _positions[node.id] = previous;
        _velocities[node.id] = previousVelocities[node.id] ?? Offset.zero;
        if (previousPinned.contains(node.id)) _pinned.add(node.id);
      }
    }

    _iterations = 0;
    _kineticEnergy = double.infinity;
  }

  /// Moves [nodeId] to [position] in layout space and pins it there. Used for
  /// drag interaction; a pinned node is skipped by the integrator.
  void pin(String nodeId, Offset position) {
    if (!_positions.containsKey(nodeId)) return;
    _positions[nodeId] = position;
    _velocities[nodeId] = Offset.zero;
    _pinned.add(nodeId);
  }

  /// Moves [nodeId] without pinning it.
  void moveNode(String nodeId, Offset position) {
    if (!_positions.containsKey(nodeId)) return;
    _positions[nodeId] = position;
  }

  /// Releases a pinned node so the simulation can move it again.
  void unpin(String nodeId) {
    _pinned.remove(nodeId);
    _kineticEnergy = double.infinity;
  }

  /// Releases every pinned node.
  void unpinAll() {
    _pinned.clear();
    _kineticEnergy = double.infinity;
  }

  // ── Output ─────────────────────────────────────────────────────────────────

  /// Bounding box of the current positions, or null when empty.
  Rect? bounds() {
    if (_positions.isEmpty) return null;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final position in _positions.values) {
      minX = math.min(minX, position.dx);
      minY = math.min(minY, position.dy);
      maxX = math.max(maxX, position.dx);
      maxY = math.max(maxY, position.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Maps the current positions into [size] with [padding] on every edge,
  /// preserving aspect ratio and centering the result. Scale is clamped to
  /// `[0.15, 1.0]` so a two-node graph is not blown up to fill a wide viewport.
  Map<String, Offset> fitToSize(Size size, {double padding = 48.0}) {
    final box = bounds();
    if (box == null) return const <String, Offset>{};

    final spanX = math.max(box.width, 1e-3);
    final spanY = math.max(box.height, 1e-3);
    final availableWidth = math.max(size.width - padding * 2, 1.0);
    final availableHeight = math.max(size.height - padding * 2, 1.0);
    final scale = math
        .min(availableWidth / spanX, availableHeight / spanY)
        .clamp(0.15, 1.0);

    final center = box.center;
    final target = Offset(size.width / 2, size.height / 2);
    return <String, Offset>{
      for (final entry in _positions.entries)
        entry.key: target + (entry.value - center) * scale,
    };
  }
}

/// Derives a stable simulated depth in `0..1` per node from graph topology.
///
/// Nodes with no incoming edges (the graph's inputs) are nearest the viewer at
/// `1.0`; each BFS tier toward the outputs recedes. [jitter] adds a small
/// deterministic offset derived from the node id so nodes in the same tier do
/// not render on one perfectly flat plane — the depth cue the 2.5D painter
/// needs to read as depth rather than as a size glitch.
Map<String, double> computeNetworkDepths(
  CanvasGraph graph, {
  double jitter = 0.35,
}) {
  if (graph.nodes.isEmpty) return const <String, double>{};

  final ids = <String>{for (final node in graph.nodes) node.id};
  final adjacency = <String, List<String>>{
    for (final id in ids) id: <String>[],
  };
  final incoming = <String, int>{for (final id in ids) id: 0};

  for (final edge in graph.edges) {
    if (!ids.contains(edge.sourceNodeId) || !ids.contains(edge.targetNodeId)) {
      continue;
    }
    adjacency[edge.sourceNodeId]!.add(edge.targetNodeId);
    incoming.update(edge.targetNodeId, (count) => count + 1, ifAbsent: () => 1);
  }

  final tier = <String, int>{};
  final queue = <String>[];
  for (final node in graph.nodes) {
    if ((incoming[node.id] ?? 0) == 0) {
      tier[node.id] = 0;
      queue.add(node.id);
    }
  }
  if (queue.isEmpty) {
    for (final node in graph.nodes) {
      tier[node.id] = 0;
      queue.add(node.id);
    }
  }

  var cursor = 0;
  while (cursor < queue.length) {
    final current = queue[cursor++];
    for (final next in adjacency[current] ?? const <String>[]) {
      if (tier.containsKey(next)) continue;
      tier[next] = tier[current]! + 1;
      queue.add(next);
    }
  }
  for (final node in graph.nodes) {
    tier.putIfAbsent(node.id, () => 0);
  }

  final maxTier = tier.values.fold<int>(0, math.max);
  final jitterRange = jitter.clamp(0.0, 1.0);
  return <String, double>{
    for (final node in graph.nodes)
      node.id: _depthFor(
        tier: tier[node.id]!,
        maxTier: maxTier,
        id: node.id,
        jitter: jitterRange,
      ),
  };
}

double _depthFor({
  required int tier,
  required int maxTier,
  required String id,
  required double jitter,
}) {
  final ordering = maxTier <= 0 ? 1.0 : 1.0 - tier / maxTier;
  final offset = (_stableUnit(id) - 0.5) * jitter;
  return (ordering + offset).clamp(0.0, 1.0);
}

/// FNV-1a based `0..1` hash. Stable across runs, unlike [Object.hashCode].
double _stableUnit(String value) {
  var hash = 2166136261;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0xFFFFFFFF;
  }
  return (hash % 10000) / 10000.0;
}
