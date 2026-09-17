import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';

/// An immutable point in the globe layout's origin-centred 3D space.
///
/// The layout is pure math, so it uses this tiny value type instead of a
/// Flutter/`dart:ui` type. That keeps the engine usable from any renderer and
/// directly unit-testable without a widget binding.
class GlobePoint {
  const GlobePoint(this.x, this.y, this.z);

  static const GlobePoint origin = GlobePoint(0, 0, 0);

  final double x;
  final double y;
  final double z;

  /// Euclidean distance from the origin.
  double get distance => math.sqrt(x * x + y * y + z * z);

  GlobePoint operator +(GlobePoint other) =>
      GlobePoint(x + other.x, y + other.y, z + other.z);

  GlobePoint operator -(GlobePoint other) =>
      GlobePoint(x - other.x, y - other.y, z - other.z);

  GlobePoint operator *(double scalar) =>
      GlobePoint(x * scalar, y * scalar, z * scalar);

  /// A copy of this point moved onto the sphere of [radius] through the origin,
  /// keeping its direction. The origin maps to itself.
  GlobePoint scaledTo(double radius) {
    final current = distance;
    if (current == 0) return origin;
    return this * (radius / current);
  }

  @override
  bool operator ==(Object other) =>
      other is GlobePoint && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'GlobePoint($x, $y, $z)';
}

/// Resolves the grouping category (the sphere "sector") for a canvas node.
///
/// In the network view this is the node's layer type, which drives both the
/// node color and the slice of the sphere it occupies. The engine stays
/// registry-agnostic by taking a resolver; the caller can read the NIR node
/// registry, while [GlobeLayout.defaultCategoryOf] provides a registry-free
/// fallback for tests and for graphs without NIR metadata.
typedef GlobeCategoryResolver = String Function(CanvasNode node);

/// Tunable parameters for [GlobeLayout].
///
/// The defaults reproduce the AIS-OS `composeGlobe` constants, tuned for the
/// network view's granularity — layers/components (tens of nodes), not raw
/// neurons. The placement is the "equal-area" technique from that view:
///
/// * **latitude** — nodes in a category are spread on equal-area bands, so the
///   silhouette reads as a round sphere from every camera angle;
/// * **golden turn** — consecutive nodes in a category advance their azimuth by
///   an irrational fraction of a turn, so they never clump or form spokes;
/// * **sector** — each category owns one slice of the full azimuth, so layer
///   types stay visually grouped;
/// * **radial turn** — a second irrational fraction jitters the orbit radius,
///   so nodes are not all pinned to one perfect shell.
class GlobeLayoutConfig {
  const GlobeLayoutConfig({
    this.baseRadius = 350.0,
    this.radiusJitter = 100.0,
    this.sectorInset = 0.08,
    this.sectorFill = 0.84,
    this.goldenTurn = 0.61803398875,
    this.radialTurn = 0.754877666,
    this.fallbackCategory = 'other',
  });

  /// Radius of the innermost orbit shell.
  final double baseRadius;

  /// Extra radius added by the [radialTurn] jitter. Orbits span
  /// `[baseRadius, baseRadius + radiusJitter)`.
  final double radiusJitter;

  /// Fraction of a category's azimuth slice left empty at each edge, so
  /// neighbouring categories never touch.
  final double sectorInset;

  /// Fraction of a category's azimuth slice actually used by its nodes.
  /// `sectorInset + sectorFill` must be at most `1`.
  final double sectorFill;

  /// Fraction of a full turn between consecutive nodes in a category. The
  /// default is the golden ratio conjugate `1 / φ`, the classic low-discrepancy
  /// sequence that avoids both clumping and visible rows.
  final double goldenTurn;

  /// Fraction of a full turn used to jitter the orbit radius between nodes.
  final double radialTurn;

  /// Category used when a resolver returns an empty string.
  final String fallbackCategory;

  GlobeLayoutConfig copyWith({
    double? baseRadius,
    double? radiusJitter,
    double? sectorInset,
    double? sectorFill,
    double? goldenTurn,
    double? radialTurn,
    String? fallbackCategory,
  }) {
    return GlobeLayoutConfig(
      baseRadius: baseRadius ?? this.baseRadius,
      radiusJitter: radiusJitter ?? this.radiusJitter,
      sectorInset: sectorInset ?? this.sectorInset,
      sectorFill: sectorFill ?? this.sectorFill,
      goldenTurn: goldenTurn ?? this.goldenTurn,
      radialTurn: radialTurn ?? this.radialTurn,
      fallbackCategory: fallbackCategory ?? this.fallbackCategory,
    );
  }
}

/// The computed placement of one node on the globe.
class GlobeNodePlacement {
  const GlobeNodePlacement({
    required this.id,
    required this.category,
    required this.sector,
    required this.position,
    required this.radius,
  });

  /// The node id this placement belongs to.
  final String id;

  /// Grouping category (layer type) that selected the sphere sector.
  final String category;

  /// Index of [category] in [GlobeLayout.sectors].
  final int sector;

  /// Origin-centred 3D position.
  final GlobePoint position;

  /// Distance of [position] from the origin, in `[baseRadius,
  /// baseRadius + radiusJitter)`.
  final double radius;
}

/// Deterministic spherical layout for a [CanvasGraph].
///
/// This is the `composeGlobe`-equivalent from the AIS-OS `/3d-brain` view,
/// ported to pure Dart. It groups nodes by category (layer type), gives each
/// category its own azimuth sector, and samples each node onto an equal-area
/// latitude band of a sphere. There is no rendering dependency and no
/// randomness: the same graph always yields the same positions, which keeps the
/// view stable across rebuilds and makes the layout directly unit-testable.
///
/// The result is origin-centred; use [scaledToRadius] to map the outermost
/// orbit onto a concrete viewport before projecting.
class GlobeLayout {
  GlobeLayout(
    CanvasGraph graph, {
    this.config = const GlobeLayoutConfig(),
    GlobeCategoryResolver? categoryOf,
    this.sectorOrder,
  }) : categoryOf = categoryOf ?? defaultCategoryOf {
    _compute(graph);
  }

  final GlobeLayoutConfig config;
  final GlobeCategoryResolver categoryOf;

  /// Optional explicit sector ordering, mirroring the `sources` argument of the
  /// AIS-OS `composeGlobe`. When set, every listed category that is present in
  /// the graph keeps its given slot; any remaining categories are appended in
  /// sorted order. When `null`, sectors are simply sorted alphabetically.
  final List<String>? sectorOrder;

  final Map<String, GlobeNodePlacement> _placements =
      <String, GlobeNodePlacement>{};
  List<String> _sectors = const <String>[];

  /// Placement per node id, in the graph's node order.
  Map<String, GlobeNodePlacement> get placements =>
      Map<String, GlobeNodePlacement>.unmodifiable(_placements);

  /// Categories that own a sector, sorted deterministically. The index of a
  /// category in this list is its [GlobeNodePlacement.sector].
  List<String> get sectors => List<String>.unmodifiable(_sectors);

  /// Position per node id.
  Map<String, GlobePoint> get positions => <String, GlobePoint>{
    for (final entry in _placements.entries) entry.key: entry.value.position,
  };

  /// Radius of the outermost orbit, or `0` when the layout is empty.
  double get boundingRadius => _placements.values.fold<double>(
    0,
    (max, placement) => math.max(max, placement.radius),
  );

  /// The placement for [nodeId], or `null` when the node is not in the graph.
  GlobeNodePlacement? placementOf(String nodeId) => _placements[nodeId];

  /// Sector index for [nodeId], or `-1` when the node is not in the graph.
  int sectorOf(String nodeId) => _placements[nodeId]?.sector ?? -1;

  /// Category for [nodeId], or the config fallback when not in the graph.
  String categoryOfNode(String nodeId) =>
      _placements[nodeId]?.category ?? config.fallbackCategory;

  /// Uniformly scales every position so the outermost node sits at [radius],
  /// preserving the relative orbit shells. Returns an empty map when the layout
  /// is empty. A non-positive [radius] returns the unscaled positions.
  Map<String, GlobePoint> scaledToRadius(double radius) {
    final outermost = boundingRadius;
    if (outermost <= 0 || radius <= 0) return positions;
    final factor = radius / outermost;
    return <String, GlobePoint>{
      for (final entry in _placements.entries)
        entry.key: entry.value.position * factor,
    };
  }

  /// Registry-free category resolution: prefer an explicit
  /// `metadata['category']`, then the node's NIR type, then its component id.
  static String defaultCategoryOf(CanvasNode node) {
    final metadataCategory = node.metadata['category'];
    if (metadataCategory is String && metadataCategory.isNotEmpty) {
      return metadataCategory;
    }
    final nirType = node.nirType;
    if (nirType != null && nirType.isNotEmpty) return nirType;
    return node.componentId;
  }

  void _compute(CanvasGraph graph) {
    _placements.clear();
    _sectors = const <String>[];

    final byCategory = <String, List<CanvasNode>>{};
    for (final node in graph.nodes) {
      final resolved = categoryOf(node).trim();
      final category = resolved.isEmpty ? config.fallbackCategory : resolved;
      byCategory.putIfAbsent(category, () => <CanvasNode>[]).add(node);
    }
    if (byCategory.isEmpty) return;

    final requested = sectorOrder;
    final known = <String>{...byCategory.keys};
    final sectors = <String>[];
    if (requested == null) {
      sectors.addAll(known.toList(growable: false)..sort());
    } else {
      sectors.addAll(requested.where(known.contains));
      sectors.addAll(
        (known.difference(requested.toSet()).toList(growable: false)..sort()),
      );
    }
    final sectorCount = sectors.length;

    for (var sector = 0; sector < sectorCount; sector++) {
      final category = sectors[sector];
      final nodes = byCategory[category]!..sort((a, b) => a.id.compareTo(b.id));
      final count = nodes.length;

      for (var i = 0; i < count; i++) {
        final node = nodes[i];

        // Equal-area latitude bands: uniform in y = sin(latitude), so every
        // band covers the same surface area and the silhouette stays round.
        final latitude = 1 - 2 * ((i + 0.5) / count);

        // Golden-angle azimuth within the category's own sector slice.
        final turn = (i * config.goldenTurn) % 1;
        final azimuthFraction =
            (sector + config.sectorInset + turn * config.sectorFill) /
            sectorCount;
        final azimuth = azimuthFraction * 2 * math.pi;

        // A second irrational turn jitters the orbit radius.
        final radius =
            config.baseRadius +
            config.radiusJitter * ((i * config.radialTurn) % 1);

        final horizontal = math.sqrt(math.max(0.0, 1 - latitude * latitude));
        final position = GlobePoint(
          radius * horizontal * math.sin(azimuth),
          radius * latitude,
          radius * horizontal * math.cos(azimuth),
        );

        _placements[node.id] = GlobeNodePlacement(
          id: node.id,
          category: category,
          sector: sector,
          position: position,
          radius: radius,
        );
      }
    }

    _sectors = sectors;
  }
}

/// 2D layout + depth derived from a [GlobeLayout] for [Network25DView].
///
/// Positions use the globe's horizontal plane (`x`, `y`); depth comes from `z`
/// so the orbit camera can rotate the sphere without re-running placement.
class GlobeNetworkLayout {
  GlobeNetworkLayout(
    CanvasGraph graph, {
    GlobeCategoryResolver? categoryOf,
    List<String>? sectorOrder,
  }) : _globe = GlobeLayout(
         graph,
         categoryOf: categoryOf,
         sectorOrder: sectorOrder,
       ) {
    _syncFromGlobe();
  }

  GlobeLayout _globe;
  final Map<String, Offset> _positions = <String, Offset>{};
  final Map<String, double> _depths = <String, double>{};
  final Set<String> _pinned = <String>{};

  /// Globe layout is static — never needs a relax ticker.
  bool get isSettled => true;

  Map<String, Offset> get positions =>
      Map<String, Offset>.unmodifiable(_positions);

  Map<String, double> get depths => Map<String, double>.unmodifiable(_depths);

  void updateGraph(
    CanvasGraph graph, {
    GlobeCategoryResolver? categoryOf,
    List<String>? sectorOrder,
  }) {
    final previousPositions = Map<String, Offset>.from(_positions);
    final previousPinned = Set<String>.from(_pinned);
    _globe = GlobeLayout(
      graph,
      categoryOf: categoryOf,
      sectorOrder: sectorOrder,
    );
    _syncFromGlobe();
    for (final id in previousPinned) {
      final previous = previousPositions[id];
      if (previous != null && _positions.containsKey(id)) {
        pin(id, previous);
      }
    }
  }

  void pin(String nodeId, Offset position) {
    if (!_positions.containsKey(nodeId)) return;
    _positions[nodeId] = position;
    _pinned.add(nodeId);
  }

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

  void _syncFromGlobe() {
    _positions.clear();
    _depths.clear();
    final outer = _globe.boundingRadius;
    for (final placement in _globe.placements.values) {
      final point = placement.position;
      _positions[placement.id] = Offset(point.x, point.y);
      _depths[placement.id] = outer <= 0 ? 0.5 : ((point.z / outer) + 1) / 2;
    }
    _pinned.removeWhere((id) => !_positions.containsKey(id));
  }

  /// Category resolver that prefers the NIR type registry, then metadata.
  static GlobeCategoryResolver categoryResolver(
    Map<String, NirNodeType>? nirTypes,
  ) {
    if (nirTypes == null) return GlobeLayout.defaultCategoryOf;
    return (CanvasNode node) {
      final type = nirTypes[node.nirType ?? node.componentId];
      if (type != null && type.category.isNotEmpty) return type.category;
      return GlobeLayout.defaultCategoryOf(node);
    };
  }
}
