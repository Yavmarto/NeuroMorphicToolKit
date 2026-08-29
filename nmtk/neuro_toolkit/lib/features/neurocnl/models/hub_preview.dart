enum HubVisibility { public, private }

enum HubArtefactKind { workspace, benchmarkResult, customNode }

/// The local preview's signed-in identity. Profile ownership and newly shared
/// preview items must use this value rather than a separate "You" placeholder.
const String kHubCurrentUserName = 'Maya Chen';

class HubDetailField {
  const HubDetailField({required this.label, required this.value});

  final String label;
  final String value;
}

class HubArtefactDetail {
  const HubArtefactDetail({
    required this.overview,
    this.fields = const <HubDetailField>[],
  });

  final String overview;
  final List<HubDetailField> fields;
}

class HubArtefactPreview {
  const HubArtefactPreview({
    required this.id,
    required this.title,
    required this.kind,
    required this.description,
    required this.author,
    required this.visibility,
    required this.updatedLabel,
    required this.recency,
    required this.popularity,
    required this.detail,
    this.tags = const <String>[],
    this.metric,
    this.rawWorkspace,
  });

  final String id;
  final String title;
  final HubArtefactKind kind;
  final String description;
  final String author;
  final HubVisibility visibility;
  final List<String> tags;
  final String? metric;
  final String updatedLabel;
  final int recency;
  final int popularity;
  final HubArtefactDetail detail;
  final Map<String, dynamic>? rawWorkspace;

  HubArtefactPreview copyWith({HubVisibility? visibility}) =>
      HubArtefactPreview(
        id: id,
        title: title,
        kind: kind,
        description: description,
        author: author,
        visibility: visibility ?? this.visibility,
        tags: tags,
        metric: metric,
        updatedLabel: updatedLabel,
        recency: recency,
        popularity: popularity,
        detail: detail,
        rawWorkspace: rawWorkspace,
      );

  String get kindLabel => switch (kind) {
    HubArtefactKind.workspace => 'Workspace',
    HubArtefactKind.benchmarkResult => 'Benchmark result',
    HubArtefactKind.customNode => 'Custom node',
  };

  String get searchableText => <String>[
    title,
    description,
    author,
    kindLabel,
    ...tags,
    detail.overview,
    ...detail.fields.expand((field) => <String>[field.label, field.value]),
  ].join(' ').toLowerCase();
}

const List<HubArtefactPreview> kHubPreviewArtefacts = <HubArtefactPreview>[
  HubArtefactPreview(
    id: 'gesture-workspace',
    title: 'Gesture classifier workspace',
    kind: HubArtefactKind.workspace,
    description: 'A ready-to-run event-stream classifier with an Akida target.',
    author: kHubCurrentUserName,
    visibility: HubVisibility.public,
    updatedLabel: 'Updated today',
    recency: 4,
    popularity: 82,
    tags: <String>['vision', 'akida'],
    detail: HubArtefactDetail(
      overview:
          'A complete gesture-recognition pipeline prepared for event-camera input.',
      fields: <HubDetailField>[
        HubDetailField(label: 'Pipeline', value: 'Event stream → SNN → Akida'),
        HubDetailField(label: 'Target', value: 'BrainChip Akida'),
        HubDetailField(label: 'Files', value: '4 workspace files'),
      ],
    ),
  ),
  HubArtefactPreview(
    id: 'private-sweep',
    title: 'Adaptive threshold sweep',
    kind: HubArtefactKind.benchmarkResult,
    description: 'Private comparison run for the current workspace.',
    author: kHubCurrentUserName,
    visibility: HubVisibility.private,
    updatedLabel: 'Updated yesterday',
    recency: 3,
    popularity: 0,
    tags: <String>['sweep', 'threshold'],
    metric: '18.4 ms latency',
    detail: HubArtefactDetail(
      overview:
          'A private parameter sweep comparing adaptive threshold settings.',
      fields: <HubDetailField>[
        HubDetailField(label: 'Dataset', value: 'DVSGesture validation'),
        HubDetailField(label: 'Target', value: 'NeuroSim'),
        HubDetailField(label: 'Best result', value: '18.4 ms latency'),
      ],
    ),
  ),
  HubArtefactPreview(
    id: 'temporal-node',
    title: 'Temporal pooling node',
    kind: HubArtefactKind.customNode,
    description: 'Reusable node for sparse temporal feature pooling.',
    author: kHubCurrentUserName,
    visibility: HubVisibility.public,
    updatedLabel: 'Updated 3 days ago',
    recency: 2,
    popularity: 64,
    tags: <String>['custom-node', 'snn'],
    detail: HubArtefactDetail(
      overview:
          'Pools sparse spike features over a configurable temporal window.',
      fields: <HubDetailField>[
        HubDetailField(label: 'Input', value: 'Sparse spike tensor'),
        HubDetailField(label: 'Output', value: 'Pooled feature tensor'),
        HubDetailField(label: 'Parameters', value: 'window_ms, stride_ms'),
      ],
    ),
  ),
  HubArtefactPreview(
    id: 'mnist-benchmark',
    title: 'MNIST Akida benchmark',
    kind: HubArtefactKind.benchmarkResult,
    description: 'Reproducible latency, accuracy, and energy measurements.',
    author: 'Ravi Patel',
    visibility: HubVisibility.public,
    updatedLabel: 'Updated 5 days ago',
    recency: 1,
    popularity: 97,
    tags: <String>['mnist', 'benchmark', 'akida'],
    metric: '96.8% accuracy',
    detail: HubArtefactDetail(
      overview:
          'A reproducible Akida benchmark with the configuration and headline results attached.',
      fields: <HubDetailField>[
        HubDetailField(label: 'Accuracy', value: '96.8%'),
        HubDetailField(label: 'Latency', value: '2.1 ms'),
        HubDetailField(label: 'Energy', value: '0.42 mJ / inference'),
      ],
    ),
  ),
  HubArtefactPreview(
    id: 'wake-word-workspace',
    title: 'Always-on wake-word workspace',
    kind: HubArtefactKind.workspace,
    description:
        'An event-driven audio pipeline tuned for low-power keyword detection.',
    author: 'Sofia Nguyen',
    visibility: HubVisibility.public,
    updatedLabel: 'Updated 6 days ago',
    recency: 0,
    popularity: 75,
    tags: <String>['audio', 'wake-word', 'edge'],
    detail: HubArtefactDetail(
      overview:
          'A compact workspace for evaluating keyword detection on an event-audio front end.',
      fields: <HubDetailField>[
        HubDetailField(
          label: 'Pipeline',
          value: 'Audio events → encoder → SNN',
        ),
        HubDetailField(label: 'Target', value: 'Edge simulator'),
        HubDetailField(label: 'Files', value: '6 workspace files'),
      ],
    ),
  ),
  HubArtefactPreview(
    id: 'loihi-latency-benchmark',
    title: 'Loihi temporal pooling benchmark',
    kind: HubArtefactKind.benchmarkResult,
    description: 'Latency and energy measurements for sparse temporal pooling.',
    author: 'Amina Okafor',
    visibility: HubVisibility.public,
    updatedLabel: 'Updated 8 days ago',
    recency: -1,
    popularity: 88,
    tags: <String>['loihi', 'benchmark', 'temporal'],
    metric: '1.7 ms latency',
    detail: HubArtefactDetail(
      overview:
          'A benchmark recipe for comparing temporal pooling on Loihi-compatible configurations.',
      fields: <HubDetailField>[
        HubDetailField(label: 'Accuracy', value: '94.2%'),
        HubDetailField(label: 'Latency', value: '1.7 ms'),
        HubDetailField(label: 'Energy', value: '0.31 mJ / inference'),
      ],
    ),
  ),
  HubArtefactPreview(
    id: 'refractory-node',
    title: 'Adaptive refractory node',
    kind: HubArtefactKind.customNode,
    description:
        'A configurable refractory gate for stabilising sparse SNN activity.',
    author: 'Jon Bell',
    visibility: HubVisibility.public,
    updatedLabel: 'Updated 12 days ago',
    recency: -2,
    popularity: 53,
    tags: <String>['custom-node', 'stability', 'snn'],
    detail: HubArtefactDetail(
      overview:
          'Controls post-spike suppression with an adaptive refractory period.',
      fields: <HubDetailField>[
        HubDetailField(label: 'Input', value: 'Spike event stream'),
        HubDetailField(label: 'Output', value: 'Gated spike event stream'),
        HubDetailField(label: 'Parameters', value: 'refractory_ms, adaptation'),
      ],
    ),
  ),
];
