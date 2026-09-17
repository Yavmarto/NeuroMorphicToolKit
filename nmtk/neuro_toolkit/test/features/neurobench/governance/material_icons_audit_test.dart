// Governance test for T-ICON (Material Icons → ZetaIcons sweep).
//
// Scope: forbids new unannotated Material `Icons.*` references in `lib/`.
//
// Mechanism (baseline ratchet):
//
//   * `kIconsBaseline` is a constant representing the current grandfathered
//     `Icons.*` hit count for this package. As T-ICON-3..5 progress, this
//     constant must be decreased monotonically. After T-ICON-5 the
//     constant must equal 0.
//   * Any `Icons.*` reference in `lib/` outside an exemption marker counts
//     toward the budget. An "exemption marker" is any line containing the
//     regex `ZETA-MIGRATION-EXEMPT:\s*\S` (typically a trailing comment on
//     the same line, or a comment on the immediately preceding line).
//   * The test asserts `iconsHits - markerCount <= kIconsBaseline`, i.e.
//     the count of *unannotated* Material Icons usages does not exceed
//     the baseline.
//
// Background: the suite uses `zeta_flutter ^1.4.5` after T-UI-9. ZetaIcons
// covers ~51% of NMTK's icon usage; the rest split between Tier B
// curated semantic mapping and Tier C1 documented exemption. See
// `.kiro/specs/material-to-zeta-icons-sweep/` and
// `docs/current tasks/2026-05-26-material-icons-to-zeta-icons-migration.md`.
//
// To migrate a `Icons.X` reference:
//   1. If the icon has a direct or normalised match in ZetaIcons, replace
//      with `ZetaIcons.<normalised>` (Tier A).
//   2. If the icon has a curated semantic equivalent in
//      `.kiro/specs/material-to-zeta-icons-sweep/design.md §Tier B`,
//      apply that substitution.
//   3. If neither applies, keep the reference and add an exemption
//      marker explaining why no Zeta equivalent exists. Example:
//
//        // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (graph hub icon)
//        const Icon(Icons.hub_outlined, size: 20)
//
//      ...or as a trailing comment:
//
//        Icon(Icons.science_outlined,
//             // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (flask)
//             color: tokens.metadataForeground)
//
// After modifying any file: `dart analyze <file>` must return zero new
// errors. After this package is fully swept: `flutter test` must pass at
// the pre-existing baseline failure count.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Current grandfathered `Icons.*` hit count for this package.
///
/// Decrement as the T-ICON sweep progresses through this package.
/// Must equal 0 after T-ICON-5 completes.
const int kIconsBaseline = 0;

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

/// Scans active (non-comment) lines in lib/*.dart for the given token.
List<_SourceMatch> _scanForToken(String token) {
  final matches = <_SourceMatch>[];
  for (final file in _allLibDartFiles()) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//') || trimmed.startsWith('///')) {
        continue; // pure comment line — not an active call site
      }
      if (RegExp(r'\bIcons.').hasMatch(line)) {
        matches.add(_SourceMatch(file: file, line: i + 1, text: line.trim()));
      }
    }
  }
  return matches;
}

/// Counts marker comments anywhere in lib/*.dart (comments included).
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
  group('T-ICON governance: Material Icons.* in lib/ is bounded', () {
    test('iconsHits - markerCount <= kIconsBaseline', () {
      final hits = _scanForToken('Icons.');
      final markerCount = _countMarkers(RegExp(r'ZETA-MIGRATION-EXEMPT:\s*\S'));
      final unannotated = hits.length - markerCount;
      expect(
        unannotated,
        lessThanOrEqualTo(kIconsBaseline),
        reason: 'Found ${hits.length} `Icons.*` references in lib/, of which '
            '$markerCount are paired with `// ZETA-MIGRATION-EXEMPT:` '
            'markers. Unannotated count: $unannotated. The baseline for '
            'this package is $kIconsBaseline.\n\n'
            'You have either (a) introduced a new Material `Icons.*` '
            'reference without an exemption marker, or (b) need to '
            'decrease `kIconsBaseline` to reflect progress on the '
            'T-ICON sweep.\n\n'
            'See `.kiro/specs/material-to-zeta-icons-sweep/` for the '
            'migration plan and `tasks.md` for sub-task ordering.\n\n'
            'First 30 hits:\n${hits.take(30).join('\n')}',
      );
    });

    test('kIconsBaseline is non-negative', () {
      expect(
        kIconsBaseline,
        greaterThanOrEqualTo(0),
        reason: 'kIconsBaseline must not go negative; the test would '
            'silently allow unannotated regressions. After T-ICON-5 the '
            'baseline must equal 0 and the absence-invariant holds via '
            'the marker count alone.',
      );
    });
  });
}
