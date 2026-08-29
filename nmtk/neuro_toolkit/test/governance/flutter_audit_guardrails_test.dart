import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// `lib/features/neurocnl/` and `lib/features/neurobench/` are excluded:
// they're merged-in package code, not written against these root
// guardrails, and each carries its own pre-existing (pre-merge)
// design-system debt that's a separate cleanup from the physical merge.
// Root's own code must still pass with zero exceptions.
Iterable<File> _launcherSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where(
      (file) =>
          file.path.endsWith('.dart') &&
          !file.path.endsWith('.g.dart') &&
          !file.path.endsWith('.freezed.dart') &&
          !file.path.startsWith('lib/features/neurocnl/') &&
          !file.path.startsWith('lib/features/neurobench/'),
    );

String _activeSource(File file) => file
    .readAsLinesSync()
    .where((line) {
      final trimmed = line.trimLeft();
      return !trimmed.startsWith('//') && !trimmed.startsWith('///');
    })
    .join('\n');

void main() {
  test('styled launcher controls stay behind Zeta or NMTK APIs', () {
    final forbidden = <RegExp>[
      RegExp(r'\bAlertDialog\s*\('),
      RegExp(r'\bTextField\s*\('),
      RegExp(r'\bSwitchListTile\s*\('),
      RegExp(r'\bChoiceChip\s*\('),
      RegExp(r'\bDropdownButton(?:<[^>]+>)?\s*\('),
      RegExp(r'\bIconButton\s*\('),
      RegExp(r'\bInkWell\s*\('),
      RegExp(r'\bMaterial\s*\('),
      RegExp(r'\b(?:Circular|Linear)ProgressIndicator\s*\('),
    ];
    final failures = <String>[];
    for (final file in _launcherSources()) {
      final source = _activeSource(file);
      for (final pattern in forbidden) {
        if (pattern.hasMatch(source)) failures.add('${file.path}: $pattern');
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('launcher styling uses tokens and registered fonts', () {
    final forbidden = <RegExp>[
      RegExp(r'BorderRadius\.circular\(\s*\d'),
      RegExp(r'Radius\.circular\(\s*\d'),
      RegExp("fontFamily\\s*:\\s*['\\\"]"),
      RegExp(r'Animated(?:Padding|Container|Positioned|Align|Size)\s*\('),
    ];
    final failures = <String>[];
    for (final file in _launcherSources()) {
      final source = _activeSource(file);
      for (final pattern in forbidden) {
        if (pattern.hasMatch(source)) failures.add('${file.path}: $pattern');
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('each handwritten Dart file declares at most one widget', () {
    final widgetDeclaration = RegExp(
      r'^class\s+\w+\s+extends\s+'
      r'(?:ConsumerWidget|ConsumerStatefulWidget|StatefulWidget|StatelessWidget)\b',
      multiLine: true,
    );
    final failures = <String>[];
    for (final file in _launcherSources()) {
      final count = widgetDeclaration.allMatches(_activeSource(file)).length;
      if (count > 1) failures.add('${file.path}: $count widgets');
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
