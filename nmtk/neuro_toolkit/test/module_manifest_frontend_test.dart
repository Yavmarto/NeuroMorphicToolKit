import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('modules without Flutter frontends stay out of launcher navigation', () {
    final manifest = jsonDecode(
      File('assets/modules.json').readAsStringSync(),
    ) as List<dynamic>;

    for (final moduleId in <String>['Neurosense', 'Neurohub']) {
      final module = manifest.cast<Map<String, dynamic>>().singleWhere(
            (entry) => entry['id'] == moduleId,
          );

      expect(module['hasFrontend'], isFalse, reason: moduleId);
      expect(module['frontendStatus'], 'No', reason: moduleId);
      expect(module['showInLauncherNav'], isFalse, reason: moduleId);
    }

    final neurobench = manifest.cast<Map<String, dynamic>>().singleWhere(
          (entry) => entry['id'] == 'Neurobench',
        );
    expect(neurobench['hasFrontend'], isTrue);
    expect(neurobench['frontendStatus'], 'Yes');
  });
}
