import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const featureRoot = 'lib/features/neurocnl/features/studio';

  test('Studio exposes one composition entry and five domain facades', () {
    const expectedFacades = <String>{
      '$featureRoot/studio_feature.dart',
      '$featureRoot/workspace/workspace_feature.dart',
      '$featureRoot/canvas/canvas_feature.dart',
      '$featureRoot/cnl/cnl_feature.dart',
      '$featureRoot/workflow/workflow_feature.dart',
      '$featureRoot/deployment/deployment_feature.dart',
    };

    for (final path in expectedFacades) {
      expect(File(path).existsSync(), isTrue, reason: 'Missing $path');
    }
  });

  test('package barrel exposes only the shell adapter and localization', () {
    final source = File('lib/features/neurocnl/neurocnl_studio.dart').readAsStringSync();

    expect(
      source,
      contains(
        "export 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart'",
      ),
    );
    expect(
      source,
      contains(
        "export 'package:neuro_toolkit/features/neurocnl/shell_adapter.dart'",
      ),
    );
    expect(
      RegExp(r'^export ', multiLine: true).allMatches(source),
      hasLength(2),
    );
  });

  test('Studio has zero part/part-of directives', () {
    final offenders = <String>[];

    void checkFile(File file) {
      final source = file.readAsStringSync();
      if (RegExp(r'^part\s', multiLine: true).hasMatch(source) ||
          RegExp(r'^part of\s', multiLine: true).hasMatch(source)) {
        offenders.add(file.path);
      }
    }

    checkFile(File('lib/features/neurocnl/screens/studio_screen.dart'));
    for (final entity in Directory(featureRoot).listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        checkFile(entity);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Studio must have zero part/part-of directives; found in: $offenders',
    );
  });

  test('Studio features never import the shell (studio_screen.dart)', () {
    // `studio_feature.dart` is the composition entry: its job is to expose
    // `StudioScreen` outward to the root app, so it alone is allowed to
    // reference the shell. Every other feature file must not reach back
    // into it.
    const compositionEntry = '$featureRoot/studio_feature.dart';
    final offenders = <String>[];

    for (final entity in Directory(featureRoot).listSync(recursive: true)) {
      if (entity is File &&
          entity.path.endsWith('.dart') &&
          entity.path != compositionEntry) {
        final source = entity.readAsStringSync();
        if (source.contains('screens/studio_screen.dart')) {
          offenders.add(entity.path);
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'The shell composes features, features never import it back. '
          'Offending files: $offenders',
    );
  });
}
