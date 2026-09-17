// Guards the CEL-73 raw-breakpoint-literal baseline.
//
// Some `lib/` files hardcode a raw pixel width as a `LayoutBuilder`
// breakpoint instead of using `NmtkShellTokens` or a named local constant.
// This test stops that debt from *growing*: a file may hold no more raw
// breakpoint literals than its allowlisted count, and a file not on the
// allowlist may hold none at all.
//
// ponytail: counted per file, not pinned to a line number. Line pinning
// broke the moment CEL-76/77 replaced a literal with a named constant —
// every later line in the file shifted and read as a new offender. If you
// fix a file, lower its count (or delete the entry); the test tells you the
// new number.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Path (relative to the `neuro_toolkit` package root) -> how many raw
/// breakpoint literals from [_knownBreakpointValues] that file is still
/// allowed to contain. Ratchet these down, never up.
const Map<String, int> _allowance = {
  // Last remaining offender from the CEL-73 baseline; the other six files
  // were fixed by CEL-76/77 (literals replaced with named constants), so
  // their entries are gone and they now ratchet at zero.
  // Owned by CEL-75 (`ui_core` shell parity) — should read
  // `NmtkShellTokens`, not a bare 360.
  'lib/ui_core/widgets/section_header.dart': 1,
};


/// Matches `constraints.maxWidth < 480` / `constraints.maxHeight < 420` style
/// raw breakpoint comparisons.
final RegExp _breakpointPattern = RegExp(
  r'\.(maxWidth|maxHeight)\s*<\s*(\d+)',
);

const Set<int> _knownBreakpointValues = {360, 420, 480, 520, 640, 700};

void main() {
  test('no file holds more raw breakpoint literals than its allowance', () {
    final counts = <String, int>{};
    final detail = <String, List<String>>{};

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // Normalize to the same relative, forward-slash style as the
      // allowance keys regardless of platform path separators.
      final path = entity.path.replaceAll(r'\', '/');
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final match in _breakpointPattern.allMatches(lines[i])) {
          final value = int.parse(match.group(2)!);
          if (!_knownBreakpointValues.contains(value)) continue;
          counts[path] = (counts[path] ?? 0) + 1;
          (detail[path] ??= <String>[]).add('  line ${i + 1}: < $value');
        }
      }
    }

    final failures = <String>[];
    for (final entry in counts.entries) {
      final allowed = _allowance[entry.key] ?? 0;
      if (entry.value > allowed) {
        failures.add(
          '${entry.key}: ${entry.value} raw breakpoint literal(s), '
          'allowance $allowed\n${detail[entry.key]!.join('\n')}',
        );
      }
    }

    expect(
      failures,
      isEmpty,
      reason:
          'Raw breakpoint literals grew beyond the CEL-73 baseline. Use\n'
          '`NmtkShellTokens.compactBreakpoint` / `normalBreakpoint` / '
          '`wideBreakpoint`, or a named local constant with a comment:\n'
          '${failures.join('\n')}',
    );
  });

  test('allowances do not outlive the debt they track', () {
    // A stale allowance hides a regression: if a file is fixed but keeps a
    // non-zero allowance, a new literal can be added back for free.
    final stale = <String>[];
    for (final entry in _allowance.entries) {
      final file = File(entry.key);
      expect(file.existsSync(), isTrue, reason: '${entry.key} must exist');
      final actual = _breakpointPattern
          .allMatches(file.readAsStringSync())
          .where((m) => _knownBreakpointValues.contains(int.parse(m.group(2)!)))
          .length;
      if (actual < entry.value) {
        stale.add('${entry.key}: allowance ${entry.value}, actual $actual');
      }
    }

    expect(
      stale,
      isEmpty,
      reason:
          'These files were fixed — lower their allowance in _allowance (or '
          'remove the entry) so the ratchet holds:\n${stale.join('\n')}',
    );
  });
}
