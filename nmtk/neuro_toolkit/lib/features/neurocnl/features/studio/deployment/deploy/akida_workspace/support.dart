library;

import 'package:flutter/widgets.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/services/studio_akida_deploy_service.dart';

const List<String> _kMetricOrder = <String>[
  'akida_accuracy',
  'akida_sim_accuracy',
  'snntorch_accuracy',
  'pytorch_accuracy',
  'onnx_accuracy',
  'latency_ms',
  'fps',
  'sdk_fps',
  'power_mw',
];

Iterable<MapEntry<String, double>> orderedMetrics(Map<String, double> metrics) {
  final entries = <MapEntry<String, double>>[];
  for (final key in _kMetricOrder) {
    if (metrics.containsKey(key)) {
      entries.add(MapEntry(key, metrics[key] as double));
    }
  }
  for (final entry in metrics.entries) {
    if (!_kMetricOrder.contains(entry.key) && entry.key != 'total_samples') {
      entries.add(entry);
    }
  }
  return entries;
}

String metricLabel(String key, {int? totalSamples}) {
  final scored = totalSamples != null && totalSamples > 0
      ? ' ($totalSamples samples)'
      : '';
  return switch (key) {
    'akida_accuracy' => 'Accuracy on card$scored',
    'akida_sim_accuracy' => 'Accuracy in Akida simulator',
    'snntorch_accuracy' => 'Accuracy before conversion (snnTorch)',
    'pytorch_accuracy' => 'Accuracy before conversion (PyTorch)',
    'onnx_accuracy' => 'Accuracy after ONNX export',
    'latency_ms' => 'Latency per sample',
    'fps' => 'Throughput',
    'sdk_fps' => 'Throughput reported by SDK',
    'power_mw' => 'Power (measured on device)',
    _ => key.replaceAll('_', ' '),
  };
}

/// Accuracy metrics arrive as 0–1 fractions and are rendered as percentages.
///
/// Matched on the suffix rather than an exact key list: `orderedMetrics`
/// appends every key the backend sends, so a new `*_accuracy` metric used to
/// land in the grid as a bare `0.9700` beside correctly formatted `97.00%`
/// tiles. Only the fraction metrics carry this suffix — latency, throughput
/// and power never reach this branch.
bool _isAccuracyMetric(String key) => key.endsWith('_accuracy');

String metricValue(String key, double value) {
  if (_isAccuracyMetric(key)) return formatAccuracy(value);
  return switch (key) {
    'latency_ms' => '${value.toStringAsFixed(3)} ms',
    'fps' || 'sdk_fps' => '${value.toStringAsFixed(1)} fps',
    'power_mw' => '${value.toStringAsFixed(1)} mW',
    _ =>
      value == value.roundToDouble()
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(4),
  };
}

/// One precision for accuracy everywhere it is shown. The metric grid and the
/// per-class chart render one directly above the other, and used to disagree.
String formatAccuracy(double fraction) =>
    '${(fraction * 100).toStringAsFixed(2)}%';

/// One precision for raw activations. The same value used to appear as `12.3`,
/// `12.3457` and `12.346` on a single screen.
String formatActivation(double value) => value.toStringAsFixed(3);

/// The one place the hardware-versus-simulator claim is worded.
///
/// A badge, not a banner: this sits inline beside a heading, and a full-width
/// block primitive squeezed into a `Row` only looked like a pill by accident.
Widget akidaProvenanceBadge(bool hardwareVerified) => NmtkStatusBadge(
  label: hardwareVerified ? 'Physical Akida verified' : 'Simulator result',
  tone: hardwareVerified ? NmtkTone.success : NmtkTone.warning,
  icon: hardwareVerified ? ZetaIcons.check_circle_outline : ZetaIcons.warning,
);

String predictionSummary(StudioAkidaModelPrediction prediction) {
  final name = prediction.labelName.trim();
  final predicted = name.isEmpty || name == '${prediction.prediction}'
      ? 'Prediction ${prediction.prediction}'
      : 'Prediction ${prediction.prediction} "$name"';
  if (prediction.label == null) return predicted;
  if (prediction.label == prediction.prediction) return '$predicted · correct';
  return '$predicted · expected ${prediction.label}';
}

String topOutputs(List<double> outputs) {
  final indexed = <MapEntry<int, double>>[
    for (var index = 0; index < outputs.length; index++)
      MapEntry(index, outputs[index]),
  ]..sort((a, b) => b.value.compareTo(a.value));
  return indexed
      .take(3)
      .map((entry) => '${entry.key}: ${formatActivation(entry.value)}')
      .join(' · ');
}
