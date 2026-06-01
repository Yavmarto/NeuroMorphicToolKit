import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/models/shell_models.dart';

class NmtkShellModePalette {
  final Color accent;
  final Color accentContainer;
  final Color accentForeground;
  final Color frameTint;

  const NmtkShellModePalette({
    required this.accent,
    required this.accentContainer,
    required this.accentForeground,
    required this.frameTint,
  });
}

class NmtkShellTokens extends ThemeExtension<NmtkShellTokens> {
  static const double compactBreakpoint = 600;
  static const double normalBreakpoint = 1080;
  static const double wideBreakpoint = 1280;

  /// Canonical 8-color palette for multi-channel instrument signal visualizations.
  static const List<Color> instrumentChannelPalette = [
    Color(0xFF06B6D4), // cyan-500
    Color(0xFF65C4C4), // cyan-400 muted
    Color(0xFF91E1E1), // cyan-300 muted
    Color(0xFFBCFBFB), // cyan-200 muted
    Color(0xFF0F766E), // teal-700
    Color(0xFF1A8080), // teal-600 muted
    Color(0xFF003535), // teal-900
    Color(0xFF0A1616), // teal-950
  ];

  final double topAppBarHeight;
  final double workspaceBarHeight;
  final double utilityPanelWidth;
  final double compactGap;
  final double sectionGap;
  final double radiusSm;
  final double radiusMd;
  final double radiusLg;
  final double radiusChip;
  final Duration fastMotion;
  final Duration standardMotion;
  final Duration emphasizedMotion;
  final Color shellBackground;
  final Color topBarBackground;
  final Color workspaceBarBackground;
  final Color utilityPanelBackground;
  final Color canvasBackground;
  final Color chromeBorder;
  final Color subtleBorder;
  final Color metadataForeground;
  final Color healthyColor;
  final Color runningColor;
  final Color degradedColor;
  final Color warningColor;
  final Color errorColor;
  final Color liveColor;
  final NmtkShellModePalette commandPalette;
  final NmtkShellModePalette studioPalette;
  final NmtkShellModePalette instrumentPalette;

  const NmtkShellTokens({
    required this.topAppBarHeight,
    required this.workspaceBarHeight,
    required this.utilityPanelWidth,
    required this.compactGap,
    required this.sectionGap,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.radiusChip,
    required this.fastMotion,
    required this.standardMotion,
    required this.emphasizedMotion,
    required this.shellBackground,
    required this.topBarBackground,
    required this.workspaceBarBackground,
    required this.utilityPanelBackground,
    required this.canvasBackground,
    required this.chromeBorder,
    required this.subtleBorder,
    required this.metadataForeground,
    required this.healthyColor,
    required this.runningColor,
    required this.degradedColor,
    required this.warningColor,
    required this.errorColor,
    required this.liveColor,
    required this.commandPalette,
    required this.studioPalette,
    required this.instrumentPalette,
  });

  factory NmtkShellTokens.fromColorScheme(
    ColorScheme colorScheme,
    Brightness brightness,
  ) {
    final isDark = brightness == Brightness.dark;
    return NmtkShellTokens(
      topAppBarHeight: 52,
      workspaceBarHeight: 48,
      utilityPanelWidth: 320,
      compactGap: 8,
      sectionGap: 16,
      radiusSm: 12,
      radiusMd: 16,
      radiusLg: 22,
      radiusChip: 999,
      fastMotion: const Duration(milliseconds: 120),
      standardMotion: const Duration(milliseconds: 180),
      emphasizedMotion: const Duration(milliseconds: 240),
      shellBackground: isDark
          ? const Color(0xFF08090A)
          : const Color(0xFFF8FAFC),
      topBarBackground: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFFFFFFF).withValues(alpha: 0.94),
      workspaceBarBackground: isDark
          ? const Color(0xFF0D1424)
          : const Color(0xFFF1F5F9),
      utilityPanelBackground: isDark
          ? const Color(0xFF111827)
          : const Color(0xFFFAFBFD),
      canvasBackground: isDark
          ? const Color(0xFF020617)
          : const Color(0xFFFFFFFF),
      chromeBorder: isDark ? const Color(0xFF243044) : const Color(0xFFD9E0EA),
      subtleBorder: isDark ? const Color(0xFF1A2436) : const Color(0xFFE7ECF3),
      metadataForeground: isDark
          ? const Color(0xFF9BA8BC)
          : const Color(0xFF5B677C),
      healthyColor: const Color(0xFF22C55E),
      runningColor: const Color(0xFF38BDF8),
      degradedColor: const Color(0xFFF59E0B),
      warningColor: const Color(0xFFF97316),
      errorColor: const Color(0xFFEF4444),
      liveColor: const Color(0xFFE11D48),
      commandPalette: NmtkShellModePalette(
        accent: colorScheme.primary,
        accentContainer: colorScheme.primaryContainer,
        accentForeground: colorScheme.onPrimaryContainer,
        frameTint: colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.08),
      ),
      studioPalette: NmtkShellModePalette(
        accent: isDark ? const Color(0xFF8B5CF6) : const Color(0xFF7C3AED),
        accentContainer: isDark
            ? const Color(0xFF251A46)
            : const Color(0xFFEDE9FE),
        accentForeground: isDark
            ? const Color(0xFFF3E8FF)
            : const Color(0xFF4C1D95),
        frameTint: const Color(
          0xFF8B5CF6,
        ).withValues(alpha: isDark ? 0.18 : 0.10),
      ),
      instrumentPalette: NmtkShellModePalette(
        accent: isDark ? const Color(0xFF06B6D4) : const Color(0xFF0F766E),
        accentContainer: isDark
            ? const Color(0xFF11313D)
            : const Color(0xFFCCFBF1),
        accentForeground: isDark
            ? const Color(0xFFCFFAFE)
            : const Color(0xFF134E4A),
        frameTint: const Color(
          0xFF0891B2,
        ).withValues(alpha: isDark ? 0.18 : 0.08),
      ),
    );
  }

  NmtkShellModePalette paletteForMode(NmtkShellMode mode) {
    return switch (mode) {
      NmtkShellMode.command => commandPalette,
      NmtkShellMode.studio => studioPalette,
      NmtkShellMode.instrument => instrumentPalette,
    };
  }

  static NmtkShellTokens of(BuildContext context) {
    // Cupertino path (post-migration): tokens are carried by an
    // [NmtkCupertinoShellScope] InheritedWidget. Look that up first so
    // Cupertino-rooted callers don't depend on Material's ThemeData.
    final scope = context
        .dependOnInheritedWidgetOfExactType<NmtkCupertinoShellScope>();
    if (scope != null) return scope.tokens;

    // Material path (pre-migration): legacy widgets still pump tokens
    // through ThemeData.extensions. This branch goes away at Task 6 of
    // .kiro/specs/cupertino-migration/.
    return Theme.of(context).extension<NmtkShellTokens>() ??
        NmtkShellTokens.fromColorScheme(
          Theme.of(context).colorScheme,
          Theme.of(context).brightness,
        );
  }

  @override
  ThemeExtension<NmtkShellTokens> copyWith({
    double? topAppBarHeight,
    double? workspaceBarHeight,
    double? utilityPanelWidth,
    double? compactGap,
    double? sectionGap,
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
    double? radiusChip,
    Duration? fastMotion,
    Duration? standardMotion,
    Duration? emphasizedMotion,
    Color? shellBackground,
    Color? topBarBackground,
    Color? workspaceBarBackground,
    Color? utilityPanelBackground,
    Color? canvasBackground,
    Color? chromeBorder,
    Color? subtleBorder,
    Color? metadataForeground,
    Color? healthyColor,
    Color? runningColor,
    Color? degradedColor,
    Color? warningColor,
    Color? errorColor,
    Color? liveColor,
    NmtkShellModePalette? commandPalette,
    NmtkShellModePalette? studioPalette,
    NmtkShellModePalette? instrumentPalette,
  }) {
    return NmtkShellTokens(
      topAppBarHeight: topAppBarHeight ?? this.topAppBarHeight,
      workspaceBarHeight: workspaceBarHeight ?? this.workspaceBarHeight,
      utilityPanelWidth: utilityPanelWidth ?? this.utilityPanelWidth,
      compactGap: compactGap ?? this.compactGap,
      sectionGap: sectionGap ?? this.sectionGap,
      radiusSm: radiusSm ?? this.radiusSm,
      radiusMd: radiusMd ?? this.radiusMd,
      radiusLg: radiusLg ?? this.radiusLg,
      radiusChip: radiusChip ?? this.radiusChip,
      fastMotion: fastMotion ?? this.fastMotion,
      standardMotion: standardMotion ?? this.standardMotion,
      emphasizedMotion: emphasizedMotion ?? this.emphasizedMotion,
      shellBackground: shellBackground ?? this.shellBackground,
      topBarBackground: topBarBackground ?? this.topBarBackground,
      workspaceBarBackground:
          workspaceBarBackground ?? this.workspaceBarBackground,
      utilityPanelBackground:
          utilityPanelBackground ?? this.utilityPanelBackground,
      canvasBackground: canvasBackground ?? this.canvasBackground,
      chromeBorder: chromeBorder ?? this.chromeBorder,
      subtleBorder: subtleBorder ?? this.subtleBorder,
      metadataForeground: metadataForeground ?? this.metadataForeground,
      healthyColor: healthyColor ?? this.healthyColor,
      runningColor: runningColor ?? this.runningColor,
      degradedColor: degradedColor ?? this.degradedColor,
      warningColor: warningColor ?? this.warningColor,
      errorColor: errorColor ?? this.errorColor,
      liveColor: liveColor ?? this.liveColor,
      commandPalette: commandPalette ?? this.commandPalette,
      studioPalette: studioPalette ?? this.studioPalette,
      instrumentPalette: instrumentPalette ?? this.instrumentPalette,
    );
  }

  @override
  ThemeExtension<NmtkShellTokens> lerp(
    covariant ThemeExtension<NmtkShellTokens>? other,
    double t,
  ) {
    if (other is! NmtkShellTokens) {
      return this;
    }

    return NmtkShellTokens(
      topAppBarHeight: _lerpDouble(topAppBarHeight, other.topAppBarHeight, t),
      workspaceBarHeight: _lerpDouble(
        workspaceBarHeight,
        other.workspaceBarHeight,
        t,
      ),
      utilityPanelWidth: _lerpDouble(
        utilityPanelWidth,
        other.utilityPanelWidth,
        t,
      ),
      compactGap: _lerpDouble(compactGap, other.compactGap, t),
      sectionGap: _lerpDouble(sectionGap, other.sectionGap, t),
      radiusSm: _lerpDouble(radiusSm, other.radiusSm, t),
      radiusMd: _lerpDouble(radiusMd, other.radiusMd, t),
      radiusLg: _lerpDouble(radiusLg, other.radiusLg, t),
      radiusChip: _lerpDouble(radiusChip, other.radiusChip, t),
      fastMotion: _lerpDuration(fastMotion, other.fastMotion, t),
      standardMotion: _lerpDuration(standardMotion, other.standardMotion, t),
      emphasizedMotion: _lerpDuration(
        emphasizedMotion,
        other.emphasizedMotion,
        t,
      ),
      shellBackground: Color.lerp(shellBackground, other.shellBackground, t)!,
      topBarBackground: Color.lerp(
        topBarBackground,
        other.topBarBackground,
        t,
      )!,
      workspaceBarBackground: Color.lerp(
        workspaceBarBackground,
        other.workspaceBarBackground,
        t,
      )!,
      utilityPanelBackground: Color.lerp(
        utilityPanelBackground,
        other.utilityPanelBackground,
        t,
      )!,
      canvasBackground: Color.lerp(
        canvasBackground,
        other.canvasBackground,
        t,
      )!,
      chromeBorder: Color.lerp(chromeBorder, other.chromeBorder, t)!,
      subtleBorder: Color.lerp(subtleBorder, other.subtleBorder, t)!,
      metadataForeground: Color.lerp(
        metadataForeground,
        other.metadataForeground,
        t,
      )!,
      healthyColor: Color.lerp(healthyColor, other.healthyColor, t)!,
      runningColor: Color.lerp(runningColor, other.runningColor, t)!,
      degradedColor: Color.lerp(degradedColor, other.degradedColor, t)!,
      warningColor: Color.lerp(warningColor, other.warningColor, t)!,
      errorColor: Color.lerp(errorColor, other.errorColor, t)!,
      liveColor: Color.lerp(liveColor, other.liveColor, t)!,
      commandPalette: _lerpPalette(commandPalette, other.commandPalette, t),
      studioPalette: _lerpPalette(studioPalette, other.studioPalette, t),
      instrumentPalette: _lerpPalette(
        instrumentPalette,
        other.instrumentPalette,
        t,
      ),
    );
  }

  static NmtkShellModePalette _lerpPalette(
    NmtkShellModePalette a,
    NmtkShellModePalette b,
    double t,
  ) {
    return NmtkShellModePalette(
      accent: Color.lerp(a.accent, b.accent, t)!,
      accentContainer: Color.lerp(a.accentContainer, b.accentContainer, t)!,
      accentForeground: Color.lerp(a.accentForeground, b.accentForeground, t)!,
      frameTint: Color.lerp(a.frameTint, b.frameTint, t)!,
    );
  }
}

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

Duration _lerpDuration(Duration a, Duration b, double t) {
  return Duration(
    microseconds: _lerpDouble(
      a.inMicroseconds.toDouble(),
      b.inMicroseconds.toDouble(),
      t,
    ).round(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CUPERTINO PATH (added in Task 2 of cupertino-migration)
//
// During the migration the [NmtkShellTokens] class still extends
// [ThemeExtension] so legacy widgets in `lib/widgets/` keep compiling
// against `Theme.of(context).extension<NmtkShellTokens>()`. After the
// migration completes (Task 6/7) the [ThemeExtension] ancestry is
// removed, leaving the plain class plus the [NmtkCupertinoShellScope]
// carrier defined below.
// ─────────────────────────────────────────────────────────────────────────────

extension NmtkShellTokensCupertinoFactory on NmtkShellTokens {
  /// Builds a [NmtkShellTokens] instance from a Cupertino theme.
  ///
  /// Cupertino has no `ColorScheme`, so the accent palettes are
  /// derived from [CupertinoThemeData.primaryColor] plus brightness-
  /// dependent constants matching the Material build. Module-specific
  /// accents (Studio violet, Instrument cyan) match
  /// [NmtkShellTokens.fromColorScheme] one-for-one so widgets that
  /// switch between Material and Cupertino hosts during migration see
  /// identical visual output.
  static NmtkShellTokens fromCupertinoTheme(
    CupertinoThemeData theme,
    Brightness brightness,
  ) {
    final isDark = brightness == Brightness.dark;
    final primary = theme.primaryColor;
    return NmtkShellTokens(
      topAppBarHeight: 52,
      workspaceBarHeight: 48,
      utilityPanelWidth: 320,
      compactGap: 8,
      sectionGap: 16,
      radiusSm: 12,
      radiusMd: 16,
      radiusLg: 22,
      radiusChip: 999,
      fastMotion: const Duration(milliseconds: 120),
      standardMotion: const Duration(milliseconds: 180),
      emphasizedMotion: const Duration(milliseconds: 240),
      shellBackground: isDark
          ? const Color(0xFF08090A)
          : const Color(0xFFF8FAFC),
      topBarBackground: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFFFFFFF).withValues(alpha: 0.94),
      workspaceBarBackground: isDark
          ? const Color(0xFF0D1424)
          : const Color(0xFFF1F5F9),
      utilityPanelBackground: isDark
          ? const Color(0xFF111827)
          : const Color(0xFFFAFBFD),
      canvasBackground: isDark
          ? const Color(0xFF020617)
          : const Color(0xFFFFFFFF),
      chromeBorder:
          isDark ? const Color(0xFF243044) : const Color(0xFFD9E0EA),
      subtleBorder:
          isDark ? const Color(0xFF1A2436) : const Color(0xFFE7ECF3),
      metadataForeground:
          isDark ? const Color(0xFF9BA8BC) : const Color(0xFF5B677C),
      healthyColor: const Color(0xFF22C55E),
      runningColor: const Color(0xFF38BDF8),
      degradedColor: const Color(0xFFF59E0B),
      warningColor: const Color(0xFFF97316),
      errorColor: const Color(0xFFEF4444),
      liveColor: const Color(0xFFE11D48),
      commandPalette: NmtkShellModePalette(
        accent: primary,
        accentContainer: primary.withValues(alpha: isDark ? 0.22 : 0.12),
        accentForeground: isDark
            ? const Color(0xFFEFF6FF)
            : const Color(0xFF1E3A8A),
        frameTint: primary.withValues(alpha: isDark ? 0.18 : 0.08),
      ),
      studioPalette: NmtkShellModePalette(
        accent:
            isDark ? const Color(0xFF8B5CF6) : const Color(0xFF7C3AED),
        accentContainer:
            isDark ? const Color(0xFF251A46) : const Color(0xFFEDE9FE),
        accentForeground:
            isDark ? const Color(0xFFF3E8FF) : const Color(0xFF4C1D95),
        frameTint: const Color(0xFF8B5CF6)
            .withValues(alpha: isDark ? 0.18 : 0.10),
      ),
      instrumentPalette: NmtkShellModePalette(
        accent:
            isDark ? const Color(0xFF06B6D4) : const Color(0xFF0F766E),
        accentContainer:
            isDark ? const Color(0xFF11313D) : const Color(0xFFCCFBF1),
        accentForeground:
            isDark ? const Color(0xFFCFFAFE) : const Color(0xFF134E4A),
        frameTint: const Color(0xFF0891B2)
            .withValues(alpha: isDark ? 0.18 : 0.08),
      ),
    );
  }
}

/// Carries [NmtkShellTokens] down a Cupertino widget tree.
///
/// Wrap a [CupertinoApp] (or any subtree that needs shell tokens) in
/// this scope:
///
/// ```dart
/// CupertinoApp(
///   theme: NmtkCupertinoTheme.dark,
///   builder: (context, child) => NmtkCupertinoShellScope(
///     tokens: NmtkShellTokensCupertinoFactory.fromCupertinoTheme(
///       CupertinoTheme.of(context),
///       MediaQuery.platformBrightnessOf(context),
///     ),
///     child: child!,
///   ),
///   home: const RootScreen(),
/// )
/// ```
///
/// Children read tokens via [NmtkShellTokens.of], which prefers this
/// scope over the legacy [ThemeExtension] path.
class NmtkCupertinoShellScope extends InheritedWidget {
  const NmtkCupertinoShellScope({
    required this.tokens,
    required super.child,
    super.key,
  });

  final NmtkShellTokens tokens;

  /// Returns the nearest [NmtkShellTokens] in the widget tree, or null.
  static NmtkShellTokens? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<NmtkCupertinoShellScope>()
        ?.tokens;
  }

  @override
  bool updateShouldNotify(NmtkCupertinoShellScope oldWidget) {
    return tokens != oldWidget.tokens;
  }
}
