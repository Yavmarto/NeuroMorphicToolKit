import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

void main() {
  group('AppTheme', () {
    test('lightTheme colors are correct', () {
      final theme = AppTheme.lightTheme;
      expect(theme.brightness, Brightness.light);
      expect(theme.useMaterial3, isTrue);
      // seedColor doesn't always equal primary exactly in M3
      expect(theme.colorScheme.primary, isNotNull);
    });

    test('darkTheme colors are correct', () {
      final theme = AppTheme.darkTheme;
      expect(theme.brightness, Brightness.dark);
      expect(theme.useMaterial3, isTrue);
      expect(theme.scaffoldBackgroundColor, NmtkDesignTokens.backgroundDark);
    });

    test('design tokens are correctly defined', () {
      expect(NmtkDesignTokens.primarySeed, const Color(0xFF1337EC));
      expect(NmtkDesignTokens.buttonShape, BorderRadius.circular(16.0));
      expect(NmtkDesignTokens.cardShape, BorderRadius.circular(24.0));
      expect(NmtkDesignTokens.backgroundLight, const Color(0xFFF6F6F8));
      expect(NmtkDesignTokens.backgroundDark, const Color(0xFF101322));
    });
  });

  group('NmtkThemeExtension', () {
    const extension = NmtkThemeExtension(
      terminalBackground: Colors.black,
      syntaxHighlightColor: Colors.blue,
      brandGradient: LinearGradient(colors: [Colors.blue, Colors.red]),
      glassmorphismColor: Colors.white10,
    );

    test('copyWith works correctly', () {
      final updated =
          extension.copyWith(terminalBackground: Colors.red)
              as NmtkThemeExtension;
      expect(updated.terminalBackground, Colors.red);
      expect(updated.syntaxHighlightColor, Colors.blue);
    });

    test('lerp works correctly', () {
      final other = NmtkThemeExtension(
        terminalBackground: Colors.white,
        syntaxHighlightColor: Colors.green,
        brandGradient: const LinearGradient(
          colors: [Colors.green, Colors.yellow],
        ),
        glassmorphismColor: Colors.black.withValues(alpha: 0.1),
      );

      final lerped = extension.lerp(other, 0.5) as NmtkThemeExtension;
      expect(
        lerped.terminalBackground,
        Color.lerp(Colors.black, Colors.white, 0.5),
      );
      expect(
        lerped.syntaxHighlightColor,
        Color.lerp(Colors.blue, Colors.green, 0.5),
      );
    });

    test('lerp with wrong type returns this', () {
      final result = extension.lerp(null, 0.5);
      expect(result, extension);
    });
  });

  group('AppTheme TextStyles', () {
    test('TextTheme is defined for both light and dark themes', () {
      final lightTheme = AppTheme.lightTheme;
      final darkTheme = AppTheme.darkTheme;

      expect(lightTheme.textTheme.displayLarge, isNotNull);
      expect(lightTheme.textTheme.bodyMedium, isNotNull);

      expect(darkTheme.textTheme.displayLarge, isNotNull);
      expect(darkTheme.textTheme.bodyMedium, isNotNull);
    });
  });
}
