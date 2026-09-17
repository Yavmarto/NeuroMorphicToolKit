import 'dart:convert';

/// Data model for the HDF5 tree returned by POST /api/nir/inspect.

sealed class NirHdf5Node {
  const NirHdf5Node({required this.name, required this.attrs});

  final String name;
  final Map<String, dynamic> attrs;

  factory NirHdf5Node.fromJson(Map<String, dynamic> json) {
    if (json['type'] == 'dataset') {
      return NirHdf5Dataset.fromJson(json);
    }
    return NirHdf5Group.fromJson(json);
  }

  Map<String, dynamic> toJson();
}

class NirHdf5Group extends NirHdf5Node {
  const NirHdf5Group({
    required super.name,
    required super.attrs,
    required this.children,
  });

  final List<NirHdf5Node> children;

  factory NirHdf5Group.fromJson(Map<String, dynamic> json) => NirHdf5Group(
    name: json['name'] as String,
    attrs: Map<String, dynamic>.from(json['attrs'] as Map? ?? {}),
    children: (json['children'] as List? ?? [])
        .map((c) => NirHdf5Node.fromJson(c as Map<String, dynamic>))
        .toList(),
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'group',
    'name': name,
    'attrs': attrs,
    'children': children.map((c) => c.toJson()).toList(),
  };
}

class NirHdf5Dataset extends NirHdf5Node {
  const NirHdf5Dataset({
    required super.name,
    required super.attrs,
    required this.shape,
    required this.dtype,
    required this.preview,
  });

  final List<int> shape;
  final String dtype;
  final List<dynamic>? preview;

  factory NirHdf5Dataset.fromJson(Map<String, dynamic> json) => NirHdf5Dataset(
    name: json['name'] as String,
    attrs: Map<String, dynamic>.from(json['attrs'] as Map? ?? {}),
    shape: List<int>.from(json['shape'] as List? ?? []),
    dtype: json['dtype'] as String? ?? '',
    preview: json['preview'] as List<dynamic>?,
  );

  /// Human-readable shape string, e.g. "(10, 5)".
  String get shapeLabel {
    if (shape.isEmpty) return '()';
    return '(${shape.join(', ')})';
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'dataset',
    'name': name,
    'attrs': attrs,
    'shape': shape,
    'dtype': dtype,
    'preview': preview,
  };
}

class NirInspectResult {
  const NirInspectResult({
    required this.fileName,
    required this.fileSizeBytes,
    required this.root,
  });

  final String fileName;
  final int fileSizeBytes;
  final NirHdf5Group root;

  factory NirInspectResult.fromJson(Map<String, dynamic> json) =>
      NirInspectResult(
        fileName: json['file_name'] as String,
        fileSizeBytes: json['file_size_bytes'] as int,
        root: NirHdf5Group.fromJson(json['root'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
    'file_name': fileName,
    'file_size_bytes': fileSizeBytes,
    'root': root.toJson(),
  };

  /// File size formatted as KB.
  String get sizeLabel {
    final kb = (fileSizeBytes / 1024).toStringAsFixed(1);
    return '$kb KB';
  }

  /// Build an [NirInspectResult] from the `nir_code` JSON string returned by
  /// the generate pipeline.  The JSON is `nir.NIRGraph.to_dict()` serialised,
  /// which is shaped as `{nodes: {name: {...}}, edges: [...]}`.
  factory NirInspectResult.fromNirCodeJson(String nirCode) {
    final Map<String, dynamic> decoded =
        jsonDecode(nirCode) as Map<String, dynamic>;
    return NirInspectResult(
      fileName: 'pipeline (generated)',
      fileSizeBytes: nirCode.length,
      root: NirHdf5Group(
        name: '/',
        attrs: {},
        children: decoded.entries
            .map((e) => _dynamicToNode(e.key, e.value))
            .toList(),
      ),
    );
  }
}

/// Recursively convert a JSON value into a [NirHdf5Node] tree node.
NirHdf5Node _dynamicToNode(String name, dynamic value) {
  if (value is Map<String, dynamic>) {
    return NirHdf5Group(
      name: name,
      attrs: {},
      children: value.entries
          .map((e) => _dynamicToNode(e.key, e.value))
          .toList(),
    );
  }
  if (value is List) {
    final preview = value.take(16).toList();
    return NirHdf5Dataset(
      name: name,
      attrs: {},
      shape: [value.length],
      dtype: 'list',
      preview: preview,
    );
  }
  // Scalar (number, string, bool, null)
  return NirHdf5Dataset(
    name: name,
    attrs: {},
    shape: const [],
    dtype: value == null
        ? 'null'
        : value is num
        ? 'number'
        : value is bool
        ? 'bool'
        : 'string',
    preview: value == null ? null : [value],
  );
}
