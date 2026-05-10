# Interfaces

## model_results_comparison.dart

```dart
import 'package:flutter/material.dart';

class ModelResultSummaryRow {
  const ModelResultSummaryRow({
    required this.id,
    required this.label,
    required this.hasCachedResult,
    this.durationSeconds,
    this.wallTimeSeconds,
    this.sensorySpikeCount,
    this.motorSpikeCount,
    this.sensoryMeanRateHz,
    this.motorMeanRateHz,
    this.latencyMs,
  });

  final String id;
  final String label;
  final bool hasCachedResult;
  final double? durationSeconds;
  final double? wallTimeSeconds;
  final int? sensorySpikeCount;
  final int? motorSpikeCount;
  final double? sensoryMeanRateHz;
  final double? motorMeanRateHz;
  final double? latencyMs;
}

class ModelResultsComparison extends StatelessWidget {
  const ModelResultsComparison({
    super.key,
    required this.rows,
    required this.activeId,
    required this.onSelected,
  });

  final List<ModelResultSummaryRow> rows;
  final String? activeId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    throw UnimplementedError();
  }
}
```

## model_results_comparison_test.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'model_results_comparison.dart';

void main() {
  // Add widget tests for the examples in examples.md.
}
```

## Reference Notes

- Keep this widget purely presentational.
- Use plain Material widgets only.
- The widget should remain readable on narrow widths by using wrapping or horizontal scrolling rather than overflow.
