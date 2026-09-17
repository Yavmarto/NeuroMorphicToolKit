/// Port type model and inference for canvas node connections.
// ponytail: inference + model in one file — no separate class hierarchy needed
enum ScalarType { float32, int32, boolType, any }

class PortType {
  const PortType({
    this.scalarType = ScalarType.any,
    this.rank,
    this.dims = const <int?>[],
  });

  final ScalarType scalarType;

  /// null = any rank accepted
  final int? rank;

  /// null element = wildcard dimension
  final List<int?> dims;

  bool isCompatibleWith(PortType other) {
    // Scalar type
    if (scalarType != ScalarType.any &&
        other.scalarType != ScalarType.any &&
        scalarType != other.scalarType) {
      return false;
    }
    // Rank
    if (rank != null && other.rank != null && rank != other.rank) {
      return false;
    }
    // Dims — only check paired concrete values
    for (var i = 0; i < dims.length && i < other.dims.length; i++) {
      final a = dims[i], b = other.dims[i];
      if (a != null && b != null && a != b) return false;
    }
    return true;
  }

  @override
  String toString() {
    final s = scalarType == ScalarType.any ? 'any' : scalarType.name;
    final r = rank != null ? '/rank$rank' : '';
    final d = dims.isNotEmpty
        ? '[${dims.map((x) => x?.toString() ?? '?').join(',')}]'
        : '';
    return '$s$r$d';
  }
}

// ---------------------------------------------------------------------------
// Inference
// ---------------------------------------------------------------------------

/// Returns port-id → PortType for a given NIR type and its current parameters.
/// Returns null if the type is unknown — callers treat null as "any connection OK".
Map<String, PortType>? inferNirPortTypes(
  String? nirType,
  Map<String, dynamic> params,
) {
  if (nirType == null) return null;

  const float1dAny = PortType(
    scalarType: ScalarType.float32,
    rank: 1,
    dims: <int?>[null],
  );
  const float3dAny = PortType(
    scalarType: ScalarType.float32,
    rank: 3,
    dims: <int?>[null, null, null],
  );

  int? p(String key) => params[key] as int?;

  // weight_shape is stored as a comma-separated text like '1,1,3,3'
  List<int?> parseShape(String? s) {
    if (s == null || s.isEmpty) return const <int?>[];
    return s.split(',').map((e) => int.tryParse(e.trim())).toList();
  }

  switch (nirType) {
    // --- IO ---
    case 'nir.Input':
      return {
        'out': PortType(
          scalarType: ScalarType.float32,
          rank: 1,
          dims: <int?>[p('size')],
        ),
      };
    case 'nir.Output':
      return {
        'in': PortType(
          scalarType: ScalarType.float32,
          rank: 1,
          dims: <int?>[p('size')],
        ),
      };

    // --- Neurons — typed by n_neurons ---
    case 'nir.LIF':
    case 'nir.CubaLIF':
    case 'nir.IF':
    case 'nir.LI':
    case 'cnl.Synaptic':
    case 'cnl.RSynaptic':
    case 'cnl.RLeaky':
    case 'cnl.Leaky':
      {
        final t = PortType(
          scalarType: ScalarType.float32,
          rank: 1,
          dims: <int?>[p('n_neurons')],
        );
        return {'in': t, 'out': t};
      }

    // --- Linear transforms — weight is [rows × cols] ---
    case 'nir.Linear':
    case 'nir.Affine':
      return {
        'in': PortType(
          scalarType: ScalarType.float32,
          rank: 1,
          dims: <int?>[p('cols')],
        ),
        'out': PortType(
          scalarType: ScalarType.float32,
          rank: 1,
          dims: <int?>[p('rows')],
        ),
      };

    // --- Conv1d — weight_shape: 'out_ch,in_ch,kW' ---
    case 'nir.Conv1d':
      {
        final shape = parseShape(params['weight_shape'] as String?);
        final outCh = shape.isNotEmpty ? shape[0] : null;
        final inCh = shape.length > 1 ? shape[1] : null;
        return {
          'in': PortType(
            scalarType: ScalarType.float32,
            rank: 2,
            dims: <int?>[inCh, null],
          ),
          'out': PortType(
            scalarType: ScalarType.float32,
            rank: 2,
            dims: <int?>[outCh, null],
          ),
        };
      }

    // --- Conv2d — weight_shape: 'out_ch,in_ch,kH,kW' ---
    case 'nir.Conv2d':
      {
        final shape = parseShape(params['weight_shape'] as String?);
        final outCh = shape.isNotEmpty ? shape[0] : null;
        final inCh = shape.length > 1 ? shape[1] : null;
        return {
          'in': PortType(
            scalarType: ScalarType.float32,
            rank: 3,
            dims: <int?>[inCh, null, null],
          ),
          'out': PortType(
            scalarType: ScalarType.float32,
            rank: 3,
            dims: <int?>[outCh, null, null],
          ),
        };
      }

    // --- Flatten: any-rank input → 1D output ---
    case 'nir.Flatten':
      return {
        'in': const PortType(
          scalarType: ScalarType.float32,
          // rank: null — accepts any rank
        ),
        'out': float1dAny,
      };

    // --- Pooling: 3D → 3D ---
    case 'nir.AvgPool2d':
    case 'nir.SumPool2d':
      return {'in': float3dAny, 'out': float3dAny};

    // --- Passthrough: 1D float, any size ---
    case 'nir.Scale':
    case 'nir.Delay':
    case 'cnl.Dropout':
      return {'in': float1dAny, 'out': float1dAny};

    // --- BatchNorm1d — typed by num_features ---
    case 'cnl.BatchNorm1d':
      {
        final t = PortType(
          scalarType: ScalarType.float32,
          rank: 1,
          dims: <int?>[p('num_features')],
        );
        return {'in': t, 'out': t};
      }

    default:
      return null; // unknown — allow any connection
  }
}
