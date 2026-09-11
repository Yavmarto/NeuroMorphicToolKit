import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('modules without Flutter frontends stay out of launcher navigation', () {
    final manifest =
        jsonDecode(File('assets/modules.json').readAsStringSync())
            as List<dynamic>;

    final neurosense = manifest.cast<Map<String, dynamic>>().singleWhere(
      (entry) => entry['id'] == 'Neurosense',
    );
    expect(neurosense['hasFrontend'], isFalse);
    expect(neurosense['frontendStatus'], 'No');
    expect(neurosense['showInLauncherNav'], isFalse);

    final neurobench = manifest.cast<Map<String, dynamic>>().singleWhere(
      (entry) => entry['id'] == 'Neurobench',
    );
    expect(neurobench['hasFrontend'], isTrue);
    expect(neurobench['frontendStatus'], 'Yes');

    // Neurohub ships a native Share surface in the launcher and its GitHub
    // workspace API is fronted by the same NeuroStudio client.
    final neurohub = manifest.cast<Map<String, dynamic>>().singleWhere(
      (entry) => entry['id'] == 'Neurohub',
    );
    expect(neurohub['hasFrontend'], isTrue);
    expect(neurohub['frontendStatus'], 'Yes');
    expect(neurohub['showInLauncherNav'], isTrue);
  });
}
