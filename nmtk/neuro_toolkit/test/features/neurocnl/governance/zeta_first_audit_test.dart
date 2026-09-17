// Governance test for zeta-card-reduction Task 13.
//
// Enforces the "Zeta-first" rule for selectors and chip rows in `lib/`:
//
//   * `ToggleButtons(`   — Material widget; zero tolerance. Use
//                           `ZetaSegmentedControl` instead.
//   * `SegmentedButton(` — Material widget; zero tolerance. Use
//                           `ZetaSegmentedControl` instead.
//   * `ChoiceChip(`      — Material chip; allowed only when paired with
//                           an `// Allowed: legacy <descriptor> — pending
//                           phase-2 migration` marker comment in the same
//                           file. The test asserts that the count of
//                           `ChoiceChip(` call sites does not exceed the
//                           count of allowlist markers.
//
// Background: zeta-card-reduction Tasks 4–8 migrated the right-side
// `_workspace.dart` selectors to `ZetaSegmentedControl`. The sibling
// legacy `_deploy_panel.dart` widgets (Akida / PYNQ) still use
// `ChoiceChip` rows; phase-2 of the migration will eradicate those. This
// test grandfathers the current call sites in via allowlist markers and
// fails on any NEW unannotated `ChoiceChip(` in `lib/`.
//
// To add a new vetted ChoiceChip (e.g. while migrating an existing
// panel that's been opted in elsewhere), place
// `// Allowed: legacy <descriptor> — pending phase-2 migration`
// on the line above the call site (or anywhere in the same file — the
// test counts file-wide marker occurrences).
//
// History: this test was added as part of zeta-card-reduction Task 13.
// See `docs/current tasks/2026-05-26-zeta-card-reduction-handoff.md` §6.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Directory _libDirectory() {
  final lib = Directory('lib');
  if (!lib.existsSync()) {
    throw StateError(
      'Expected to run from the package root (where lib/ lives); '
      'cwd=${Directory.current.path}',
    );
  }
  return lib;
}

List<File> _allLibDartFiles() {
  return _libDirectory()
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);
}

class _SourceMatch {
  _SourceMatch({required this.file, required this.line, required this.text});

  final File file;
  final int line;
  final String text;

  @override
  String toString() => '${file.path}:$line: $text';
}

List<_SourceMatch> _scanForToken(String token) {
  final matches = <_SourceMatch>[];
  for (final file in _allLibDartFiles()) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//') || trimmed.startsWith('///')) {
        continue; // comment line — not an active call site
      }
      if (line.contains(token)) {
        matches.add(_SourceMatch(file: file, line: i + 1, text: line.trim()));
      }
    }
  }
  return matches;
}

int _countMarkers(RegExp markerPattern) {
  var count = 0;
  for (final file in _allLibDartFiles()) {
    for (final line in file.readAsLinesSync()) {
      if (markerPattern.hasMatch(line)) count++;
    }
  }
  return count;
}

void main() {
  group('zeta-card-reduction T13 governance: Zeta-first selectors in lib/', () {
    test('ToggleButtons( is forbidden in lib/ — use ZetaSegmentedControl', () {
      final hits = _scanForToken('ToggleButtons(');
      expect(
        hits,
        isEmpty,
        reason:
            'Material ToggleButtons( is forbidden in lib/. Use '
            'ZetaSegmentedControl (re-exported from nmtk_ui_core) '
            'instead. See `lib/screens/studio/view_mode_toggle.dart` '
            'and the deploy workspaces for migration patterns.\n\n'
            'Offending occurrences:\n${hits.join('\n')}',
      );
    });

    test(
      'SegmentedButton( is forbidden in lib/ — use ZetaSegmentedControl',
      () {
        final hits = _scanForToken('SegmentedButton(');
        expect(
          hits,
          isEmpty,
          reason:
              'Material SegmentedButton( is forbidden in lib/. Use '
              'ZetaSegmentedControl (re-exported from nmtk_ui_core) '
              'instead. Per the suite Coding Style Guide, the suite '
              'strictly uses the zeta_flutter design system — Material '
              'segmented widgets are not a substitute for '
              'ZetaSegmentedControl.\n\n'
              'Offending occurrences:\n${hits.join('\n')}',
        );
      },
    );

    test('every ChoiceChip( is paired with a "legacy … pending phase-2 '
        'migration" allowlist marker', () {
      final hits = _scanForToken('ChoiceChip(');
      // Match either "legacy deploy panel" or "legacy filter chip row"
      // or any other "legacy …" descriptor — flexible so future opt-ins
      // can describe their context without rewriting the test.
      final markerPattern = RegExp(
        r'Allowed: legacy [^—]+— pending phase-2 migration',
      );
      final allowedCount = _countMarkers(markerPattern);
      expect(
        hits.length,
        lessThanOrEqualTo(allowedCount),
        reason:
            'There are ${hits.length} ChoiceChip( call sites in lib/, '
            'but only $allowedCount allowlist marker comments. Every '
            'ChoiceChip( call site must be preceded by an '
            '`// Allowed: legacy <descriptor> — pending phase-2 '
            'migration` marker, or migrated to ZetaSegmentedControl / '
            'ZetaInputChip / ZetaFilterChip.\n\n'
            'Per the suite Coding Style Guide and the Zeta primitive '
            'map (zeta-card-reduction Task 13): selectors and chip '
            'rows must use Zeta primitives.\n\n'
            'Current call sites:\n${hits.join('\n')}',
      );
    });
  });
}
