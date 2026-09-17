// Governance test for zeta-card-reduction Task 13.
//
// Locks the card-reduction migration in place by scanning every Dart source
// file under `lib/` (recursively) for tokens that the workstream eradicated:
//
//   * `NeurocnlSectionCard(`  — class deleted in T12; zero tolerance.
//   * `NmtkItemCard(`         — class deleted in T12; zero tolerance.
//   * `NmtkSurfaceCard(`      — reserved for genuine single-topic elevated
//                                surfaces. Each call site must be paired
//                                with an `// Allowed: single-topic surface`
//                                marker comment within the same file. The
//                                test asserts that the count of call sites
//                                does not exceed the count of marker
//                                comments — i.e. every NmtkSurfaceCard
//                                lives behind a vetted allowlist entry.
//
// Failure modes:
//   1. A new `NeurocnlSectionCard(` or `NmtkItemCard(` appears anywhere in
//      `lib/` — fails with the offending file + line number.
//   2. An NmtkSurfaceCard is added without an allowlist marker — fails
//      with the offending file + line number AND the current marker count.
//
// To add a new vetted single-topic NmtkSurfaceCard, place
// `// Allowed: single-topic surface` on the line immediately preceding
// the call site (or at the same nesting level — the test counts file-wide
// occurrences, so any placement works as long as the marker text appears
// in the same file).
//
// History: this test was added as part of zeta-card-reduction Task 13.
// See `docs/current tasks/2026-05-26-zeta-card-reduction-handoff.md` §6.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Resolves NeuroCNL's own `lib/` subtree. The test binary is launched from
/// the root package (per `flutter test`), and NeuroCNL now lives at
/// `lib/features/neurocnl/` inside it — scoping here (rather than to all of
/// `lib/`) keeps this governance rule limited to the domain it was written
/// for, instead of also regulating unrelated root code that never opted
/// into this convention.
Directory _libDirectory() {
  final lib = Directory('lib/features/neurocnl');
  if (!lib.existsSync()) {
    throw StateError(
      'Expected to run from the package root (where lib/features/neurocnl/ '
      'lives); cwd=${Directory.current.path}',
    );
  }
  return lib;
}

/// Returns every `*.dart` file under `lib/`, including transitive
/// subdirectories. Generated `.g.dart` / `.freezed.dart` files are
/// included because they shouldn't contain UI-card tokens either; if a
/// future generator emits one of the forbidden tokens, that's a real
/// regression worth flagging.
List<File> _allLibDartFiles() {
  return _libDirectory()
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);
}

/// One match in a source file with enough context to make a useful
/// failure message.
class _SourceMatch {
  _SourceMatch({required this.file, required this.line, required this.text});

  final File file;
  final int line;
  final String text;

  @override
  String toString() => '${file.path}:$line: $text';
}

/// Scan all `*.dart` files under `lib/` for [token]. Returns one
/// [_SourceMatch] per occurrence (one file may contribute many matches).
///
/// `// ignore: foo` lines and lines whose first non-whitespace character is
/// `//` are skipped, so the test only flags ACTIVE call sites — not
/// occurrences embedded in narrative comments / migration notes.
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

/// Scan all `*.dart` files under `lib/` for the allowlist [markerText].
/// Unlike [_scanForToken] this DOES count comment lines — markers live
/// inside `//` comments by design.
int _countMarkers(String markerText) {
  var count = 0;
  for (final file in _allLibDartFiles()) {
    for (final line in file.readAsLinesSync()) {
      if (line.contains(markerText)) count++;
    }
  }
  return count;
}

void main() {
  group('zeta-card-reduction T13 governance: no card classes in lib/', () {
    test(
      'NeurocnlSectionCard( is forbidden in lib/ (class deleted in T12)',
      () {
        final hits = _scanForToken('NeurocnlSectionCard(');
        expect(
          hits,
          isEmpty,
          reason:
              'NeurocnlSectionCard was deleted in zeta-card-reduction Task 12. '
              'Use NmtkSection (frame-less) for grouping; reserve '
              'NmtkSurfaceCard for genuine single-topic elevated surfaces. '
              'See nmtk_ui_core/docs/section_header.md.\n\n'
              'Offending occurrences:\n${hits.join('\n')}',
        );
      },
    );

    test('NmtkItemCard( is forbidden in lib/ (class deleted in T12)', () {
      final hits = _scanForToken('NmtkItemCard(');
      expect(
        hits,
        isEmpty,
        reason:
            'NmtkItemCard was deleted in zeta-card-reduction Task 12. '
            'Use ZetaListItem (re-exported from nmtk_ui_core) for list '
            'rows. See nmtk_ui_core/docs/section_header.md "When to use" '
            'matrix.\n\n'
            'Offending occurrences:\n${hits.join('\n')}',
      );
    });

    test('every NmtkSurfaceCard( is paired with an "Allowed: single-topic '
        'surface" marker comment', () {
      final hits = _scanForToken('NmtkSurfaceCard(');
      final allowedCount = _countMarkers('Allowed: single-topic surface');
      expect(
        hits.length,
        lessThanOrEqualTo(allowedCount),
        reason:
            'There are ${hits.length} NmtkSurfaceCard( call sites in '
            'lib/, but only $allowedCount '
            '"// Allowed: single-topic surface" marker comments. Every '
            'NmtkSurfaceCard call site must be preceded by this marker '
            'to document why an elevated frame is justified.\n\n'
            'Reserve NmtkSurfaceCard for single-topic elevated surfaces '
            '(zeta-card-reduction Task 13). For everything else use '
            'NmtkSection.\n\n'
            'Current call sites:\n${hits.join('\n')}',
      );
    });
  });
}
