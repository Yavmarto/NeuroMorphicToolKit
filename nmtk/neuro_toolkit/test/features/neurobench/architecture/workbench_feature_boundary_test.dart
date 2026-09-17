import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const featureRoot = 'lib/features/neurobench/features/workbench';

  test('Workbench exposes one composition entry and six domain facades', () {
    const expectedFacades = <String>{
      '$featureRoot/workbench_feature.dart',
      '$featureRoot/workspace/workspace_feature.dart',
      '$featureRoot/execution/execution_feature.dart',
      '$featureRoot/results/results_feature.dart',
      '$featureRoot/comparison/comparison_feature.dart',
      '$featureRoot/robustness/robustness_feature.dart',
      '$featureRoot/reports/reports_feature.dart',
    };

    for (final path in expectedFacades) {
      expect(File(path).existsSync(), isTrue, reason: 'Missing $path');
    }
  });
}
