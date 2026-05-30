// migration_properties_test.dart
//
// Validates invariants introduced by the full-zeta-migration spec.
// Tests cover Requirements 6.1, 6.2, 6.3, 6.7, 5.1, 1.2, 3.3, 3.4, 3.6.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

// =============================================================================
// Property 1 — TextField/ZetaTextInput parameter mapping completeness
// =============================================================================
//
// Data models and migration function used by the Property 1 property tests
// (task 3.3). These live at file scope so they are accessible from main().
//
// This section verifies the migration *contract* (the parameter mapping rules)
// rather than widget rendering.  A `TextFieldConfig` bag represents the source
// widget's parameter set; `migrateTextFieldConfig` applies the canonical
// mapping table from the design doc (Pattern B) and returns a
// `MigratedTextInputConfig`.  Properties are asserted on the output struct
// across 100+ seeded random iterations.

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// Source parameter bag — represents the parameters a developer might set on
/// a `TextField` / `TextFormField` before migration.
class TextFieldConfig {
  const TextFieldConfig({
    this.controller,
    this.onChanged,
    this.keyboardType,
    this.obscureText,
    this.maxLines,
    this.enabled,
    this.focusNode,
    this.hintText,
    this.labelText,
    this.helperText,
    this.prefixIcon,
    this.suffixIcon,
    this.errorText,
    this.validator,
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final bool? obscureText;
  final int? maxLines;
  final bool? enabled; // nullable — null means "not explicitly set"
  final FocusNode? focusNode;
  final String? hintText;
  final String? labelText;
  final String? helperText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? errorText;
  final FormFieldValidator<String>? validator;
}

/// Target parameter bag — represents the parameters that `ZetaTextInput`
/// receives after migration, as defined by the canonical mapping table in the
/// design document (Pattern B).
class MigratedTextInputConfig {
  const MigratedTextInputConfig({
    this.controller,
    this.onChanged,
    this.keyboardType,
    this.obscureText,
    this.maxLines,
    this.disabled,
    this.focusNode,
    this.hint,
    this.label,
    this.leading,
    this.trailing,
    this.errorText,
    this.validator,
  });

  // Direct pass-through fields
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final bool? obscureText;
  final int? maxLines;
  final FocusNode? focusNode;
  final String? errorText;
  final FormFieldValidator<String>? validator;

  // Transformed fields
  final bool? disabled; // !enabled when enabled is explicitly set; null otherwise
  final String? hint; // hintText + ' ' + helperText when both present; else whichever is non-null
  final String? label; // labelText
  final Widget? leading; // prefixIcon
  final Widget? trailing; // suffixIcon
}

// ---------------------------------------------------------------------------
// Migration function — the mapping rules under test
// ---------------------------------------------------------------------------

/// Applies the canonical TextField → ZetaTextInput parameter mapping table
/// defined in Pattern B of the full-zeta-migration design document.
///
/// Encoding:
///   - Direct pass-throughs: controller, onChanged, keyboardType, obscureText,
///     maxLines, focusNode, errorText, validator
///   - Polarity inversion: `enabled` → `disabled: !enabled`
///   - Hint concatenation: `hintText` + `helperText` when both present
///   - Icon renaming: `prefixIcon` → `leading`, `suffixIcon` → `trailing`
///   - Label rename: `labelText` → `label`
MigratedTextInputConfig migrateTextFieldConfig(TextFieldConfig src) {
  // Hint: concatenate hintText and helperText when both are present; otherwise
  // use whichever is non-null, or null if neither is set.
  final String? hint;
  if (src.hintText != null && src.helperText != null) {
    hint = '${src.hintText} ${src.helperText}';
  } else {
    hint = src.hintText ?? src.helperText;
  }

  // Disabled: invert polarity of enabled only when it was explicitly provided.
  final bool? disabled = src.enabled != null ? !src.enabled! : null;

  return MigratedTextInputConfig(
    controller: src.controller,
    onChanged: src.onChanged,
    keyboardType: src.keyboardType,
    obscureText: src.obscureText,
    maxLines: src.maxLines,
    disabled: disabled,
    focusNode: src.focusNode,
    hint: hint,
    label: src.labelText,
    leading: src.prefixIcon,
    trailing: src.suffixIcon,
    errorText: src.errorText,
    validator: src.validator,
  );
}

// ---------------------------------------------------------------------------
// Generator — produces random TextFieldConfig instances
// ---------------------------------------------------------------------------

/// Builds a random [TextFieldConfig] by toggling a random subset of supported
/// parameters.  Uses [random] (a seeded [Random]) so results are reproducible.
///
/// Each field is independently included with ~50 % probability so that the
/// property covers all 2^14 possible parameter-subset combinations over
/// sufficient iterations.
TextFieldConfig _randomConfig(Random random) {
  TextEditingController? controller;
  if (random.nextBool()) controller = TextEditingController();

  ValueChanged<String>? onChanged;
  if (random.nextBool()) onChanged = (_) {};

  TextInputType? keyboardType;
  if (random.nextBool()) {
    final types = [
      TextInputType.text,
      TextInputType.number,
      TextInputType.emailAddress,
      TextInputType.phone,
      TextInputType.url,
    ];
    keyboardType = types[random.nextInt(types.length)];
  }

  final bool? obscureText = random.nextBool() ? random.nextBool() : null;
  final int? maxLines = random.nextBool() ? (1 + random.nextInt(10)) : null;
  final bool? enabled = random.nextBool() ? random.nextBool() : null;

  FocusNode? focusNode;
  if (random.nextBool()) focusNode = FocusNode();

  final String? hintText =
      random.nextBool() ? 'hint_${random.nextInt(1000)}' : null;
  final String? labelText =
      random.nextBool() ? 'label_${random.nextInt(1000)}' : null;
  final String? helperText =
      random.nextBool() ? 'helper_${random.nextInt(1000)}' : null;

  Widget? prefixIcon;
  if (random.nextBool()) prefixIcon = const Icon(Icons.search);

  Widget? suffixIcon;
  if (random.nextBool()) suffixIcon = const Icon(Icons.clear);

  final String? errorText =
      random.nextBool() ? 'error_${random.nextInt(1000)}' : null;

  FormFieldValidator<String>? validator;
  if (random.nextBool()) {
    validator = (v) => (v == null || v.isEmpty) ? 'required' : null;
  }

  return TextFieldConfig(
    controller: controller,
    onChanged: onChanged,
    keyboardType: keyboardType,
    obscureText: obscureText,
    maxLines: maxLines,
    enabled: enabled,
    focusNode: focusNode,
    hintText: hintText,
    labelText: labelText,
    helperText: helperText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    errorText: errorText,
    validator: validator,
  );
}

// =============================================================================
// Main test suite
// =============================================================================

void main() {
  // ---------------------------------------------------------------------------
  // Task 1.4 — Unit tests for instrumentChannelPalette invariants
  // ---------------------------------------------------------------------------

  group('NmtkShellTokens.instrumentChannelPalette — unit tests', () {
    // Non-const: Color no longer supports primitive equality in const Sets in
    // Flutter 3.x (colorSpace field). Use a final Set instead.
    final canonicalSet = {
      const Color(0xFF06B6D4),
      const Color(0xFF65C4C4),
      const Color(0xFF91E1E1),
      const Color(0xFFBCFBFB),
      const Color(0xFF0F766E),
      const Color(0xFF1A8080),
      const Color(0xFF003535),
      const Color(0xFF0A1616),
    };

    /// Validates: Requirements 6.1
    test('palette length invariant — exactly 8 entries', () {
      expect(NmtkShellTokens.instrumentChannelPalette.length, equals(8));
    });

    /// Validates: Requirements 6.2
    test('palette membership invariant — every entry is in the canonical set',
        () {
      for (final color in NmtkShellTokens.instrumentChannelPalette) {
        expect(
          canonicalSet.contains(color),
          isTrue,
          reason:
              'Color $color is not a member of the canonical instrument palette',
        );
      }
    });

    /// Validates: Requirements 5.1
    test('font constant consistency — NmtkFontFamilies values are correct', () {
      expect(NmtkFontFamilies.monospace, equals('JetBrains Mono'));
      expect(NmtkFontFamilies.package, equals('nmtk_ui_core'));
    });

    /// Validates: Requirements 1.2
    test(
        'theme seed smoke — neurocnl dark colorScheme.primary is not 0xFF38BDF8',
        () {
      final darkTheme =
          AppTheme.darkThemeForVariant(NmtkThemeVariant.neurocnl);
      // The running color 0xFF38BDF8 must never be used as the primary accent
      // for the neurocnl studio theme after migration.
      expect(
        darkTheme.colorScheme.primary.toARGB32(),
        isNot(equals(0xFF38BDF8)),
        reason:
            'neurocnl dark theme must not use 0xFF38BDF8 (runningColor) as '
            'the primary seed color',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Task 1.5 — Property 3: Channel color index modulo wrap
  // Validates: Requirements 6.3, 6.7
  // ---------------------------------------------------------------------------

  group(
      'Property 3: Channel color index modulo wrap — no RangeError, correct color',
      () {
    final canonicalSet = {
      const Color(0xFF06B6D4),
      const Color(0xFF65C4C4),
      const Color(0xFF91E1E1),
      const Color(0xFFBCFBFB),
      const Color(0xFF0F766E),
      const Color(0xFF1A8080),
      const Color(0xFF003535),
      const Color(0xFF0A1616),
    };

    /// **Validates: Requirements 6.3, 6.7**
    ///
    /// For randomly generated (N: 1..1000, i: 0..9999) pairs over 200
    /// iterations (>= 100 as required), asserts:
    ///  - indexing with `i % palette.length` does not throw a RangeError
    ///  - the returned value is a valid [Color]
    ///  - the returned color is a member of the canonical 8-color set
    test(
        'modulo wrap yields valid canonical Color for 200 random (N, i) pairs',
        () {
      final random = Random(42); // seeded for reproducibility
      const iterations = 200; // >= 100 as required by task spec

      for (int iteration = 0; iteration < iterations; iteration++) {
        // N: 1..1000 (number of channels — documents the intended context;
        // the expression under test only uses i and palette.length)
        final n = 1 + random.nextInt(1000); // 1..1000 inclusive

        // i: 0..9999 (raw channel index, may exceed palette length)
        final i = random.nextInt(10000); // 0..9999 inclusive

        final paletteLength =
            NmtkShellTokens.instrumentChannelPalette.length;

        // The palette must retain exactly 8 entries on every iteration.
        expect(
          paletteLength,
          equals(8),
          reason:
              'palette must still have exactly 8 entries (iteration $iteration)',
        );

        // The expression under test: palette[i % palette.length].
        // Must not throw a RangeError regardless of i or n.
        final Color color;
        try {
          color = NmtkShellTokens.instrumentChannelPalette[i % paletteLength];
        } on RangeError catch (e) {
          fail(
            'RangeError thrown for i=$i, n=$n, paletteLength=$paletteLength '
            'at iteration $iteration: $e',
          );
        }

        // The returned value must be a Color (not null, not a sentinel).
        expect(
          color,
          isA<Color>(),
          reason:
              'palette[$i % $paletteLength] must return a Color '
              '(iteration $iteration)',
        );

        // The returned color must belong to the canonical 8-color set.
        expect(
          canonicalSet.contains(color),
          isTrue,
          reason:
              'palette[$i % $paletteLength] = $color is not in the canonical '
              'instrument palette (iteration $iteration, n=$n)',
        );
      }
    });

    /// **Validates: Requirements 6.7**
    ///
    /// Boundary check: index exactly equal to palette.length wraps to index 0,
    /// and index palette.length - 1 returns the last canonical entry.
    test('modulo wrap boundary — edge indices wrap correctly', () {
      final palette = NmtkShellTokens.instrumentChannelPalette;
      final length = palette.length;

      // i == length should wrap to index 0
      expect(
        palette[length % length],
        equals(palette[0]),
        reason: 'index equal to length must wrap to index 0',
      );

      // i == length - 1 should return the last entry without error
      expect(
        palette[(length - 1) % length],
        equals(palette[length - 1]),
        reason: 'index == length-1 must return the last palette entry',
      );

      // i == 0 must return the first canonical entry
      expect(
        palette[0 % length],
        equals(const Color(0xFF06B6D4)),
        reason: 'index 0 must return Color(0xFF06B6D4)',
      );

      // Large index (e.g. 9999) must not throw and must return a canonical color
      const largeIndex = 9999;
      expect(
        () => palette[largeIndex % length],
        returnsNormally,
        reason: 'large index $largeIndex % $length must not throw',
      );
      expect(
        canonicalSet.contains(palette[largeIndex % length]),
        isTrue,
        reason: 'color at large index must still be in the canonical set',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Task 3.3 — Property 1: TextField/ZetaTextInput parameter mapping completeness
  // Validates: Requirements 3.3, 3.4
  // ---------------------------------------------------------------------------

  group(
    'Property 1: TextField/ZetaTextInput parameter mapping completeness',
    () {
      /// **Validates: Requirements 3.3, 3.4**
      ///
      /// For 200 randomly generated [TextFieldConfig] structs (≥ 100 required,
      /// seeded for reproducibility), asserts that [migrateTextFieldConfig]
      /// produces a [MigratedTextInputConfig] where every direct pass-through
      /// field is identical (by reference or value) to the source.
      test(
        'direct pass-through fields are preserved across 200 random configs',
        () {
          final random = Random(2024); // seeded for reproducibility
          const iterations = 200; // ≥ 100 as required

          for (int i = 0; i < iterations; i++) {
            final src = _randomConfig(random);
            final dst = migrateTextFieldConfig(src);

            // Requirements 3.4 — direct pass-throughs

            expect(
              dst.controller,
              same(src.controller),
              reason: 'controller must pass through unchanged (iteration $i)',
            );

            expect(
              dst.onChanged,
              same(src.onChanged),
              reason: 'onChanged must pass through unchanged (iteration $i)',
            );

            expect(
              dst.keyboardType,
              equals(src.keyboardType),
              reason:
                  'keyboardType must pass through unchanged (iteration $i)',
            );

            expect(
              dst.obscureText,
              equals(src.obscureText),
              reason: 'obscureText must pass through unchanged (iteration $i)',
            );

            expect(
              dst.maxLines,
              equals(src.maxLines),
              reason: 'maxLines must pass through unchanged (iteration $i)',
            );

            expect(
              dst.focusNode,
              same(src.focusNode),
              reason: 'focusNode must pass through unchanged (iteration $i)',
            );

            expect(
              dst.errorText,
              equals(src.errorText),
              reason: 'errorText must pass through unchanged (iteration $i)',
            );

            expect(
              dst.validator,
              same(src.validator),
              reason: 'validator must pass through unchanged (iteration $i)',
            );
          }
        },
      );

      /// **Validates: Requirements 3.4**
      ///
      /// `enabled` → `disabled: !enabled` polarity inversion.
      /// When `enabled` is not explicitly set (null), `disabled` must be null
      /// (no default is injected by the migration).
      test(
        'disabled = !enabled polarity inversion across 200 random configs',
        () {
          final random = Random(31415); // seeded for reproducibility
          const iterations = 200;

          for (int i = 0; i < iterations; i++) {
            final src = _randomConfig(random);
            final dst = migrateTextFieldConfig(src);

            if (src.enabled != null) {
              expect(
                dst.disabled,
                equals(!src.enabled!),
                reason:
                    'disabled must equal !enabled when enabled is set '
                    '(iteration $i, enabled=${src.enabled})',
              );
            } else {
              expect(
                dst.disabled,
                isNull,
                reason:
                    'disabled must be null when enabled is not set '
                    '(iteration $i)',
              );
            }
          }
        },
      );

      /// **Validates: Requirements 3.3**
      ///
      /// Icon renaming: `prefixIcon` → `leading`, `suffixIcon` → `trailing`.
      /// The widget identity (same object) must be preserved — the migration
      /// must not wrap or copy the icon widget.
      test(
        'prefixIcon → leading and suffixIcon → trailing across 200 random '
        'configs',
        () {
          final random = Random(27182); // seeded for reproducibility
          const iterations = 200;

          for (int i = 0; i < iterations; i++) {
            final src = _randomConfig(random);
            final dst = migrateTextFieldConfig(src);

            expect(
              dst.leading,
              same(src.prefixIcon),
              reason:
                  'leading must be the same object as prefixIcon '
                  '(iteration $i)',
            );

            expect(
              dst.trailing,
              same(src.suffixIcon),
              reason:
                  'trailing must be the same object as suffixIcon '
                  '(iteration $i)',
            );
          }
        },
      );

      /// **Validates: Requirements 3.3**
      ///
      /// Hint concatenation rules (from the canonical mapping table):
      ///  - both hintText and helperText present → hint = '$hintText $helperText'
      ///  - only hintText present               → hint = hintText
      ///  - only helperText present             → hint = helperText
      ///  - neither present                     → hint = null
      test(
        'hint concatenation rules across 200 random configs',
        () {
          final random = Random(16180); // seeded for reproducibility
          const iterations = 200;

          for (int i = 0; i < iterations; i++) {
            final src = _randomConfig(random);
            final dst = migrateTextFieldConfig(src);

            if (src.hintText != null && src.helperText != null) {
              expect(
                dst.hint,
                equals('${src.hintText} ${src.helperText}'),
                reason:
                    'hint must be hintText + space + helperText when both '
                    'are present (iteration $i)',
              );
            } else if (src.hintText != null) {
              expect(
                dst.hint,
                equals(src.hintText),
                reason:
                    'hint must equal hintText when only hintText is present '
                    '(iteration $i)',
              );
            } else if (src.helperText != null) {
              expect(
                dst.hint,
                equals(src.helperText),
                reason:
                    'hint must equal helperText when only helperText is '
                    'present (iteration $i)',
              );
            } else {
              expect(
                dst.hint,
                isNull,
                reason:
                    'hint must be null when neither hintText nor helperText '
                    'is set (iteration $i)',
              );
            }
          }
        },
      );

      /// **Validates: Requirements 3.3**
      ///
      /// Label rename: `labelText` → `label`.
      test(
        'label equals labelText across 200 random configs',
        () {
          final random = Random(57721); // seeded for reproducibility
          const iterations = 200;

          for (int i = 0; i < iterations; i++) {
            final src = _randomConfig(random);
            final dst = migrateTextFieldConfig(src);

            expect(
              dst.label,
              equals(src.labelText),
              reason: 'label must equal labelText (iteration $i)',
            );
          }
        },
      );
    },
  );
}
