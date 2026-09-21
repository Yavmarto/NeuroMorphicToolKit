import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/contrast_utils.dart';
import 'package:neuro_toolkit/ui_core/models/shell_models.dart';

// ---------------------------------------------------------------------------
// THEME VARIANT ENUM (moved here from app_theme.dart to break circular dep)
// ---------------------------------------------------------------------------

enum NmtkThemeVariant {
  defaultNavy,
  neurocnl,
  neurohub,
  neurochip,
  neurobench,
  neurosim,
  neurosense,
}

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
  static const double compactBreakpoint = 840;
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

  // ── Fields merged from NmtkThemeExtension ──────────────────────────────────
  final Color terminalBackground;
  final Color syntaxHighlightColor;
  final LinearGradient brandGradient;
  final Color synKeyword;
  final Color synSubject;
  final Color synNumber;
  final Color synComment;
  final Color synString;
  final Color nodeEnsemble;
  final Color nodeMotor;
  final Color nodeInterneuron;
  final Color nodeGenericEnsemble;
  final Color nodeInput;
  final Color nodeErrorInput;
  final Color edgeExcitatory;
  final Color edgeInhibitory;
  final Color edgePlastic;
  final NmtkThemeVariant variant;

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
    this.terminalBackground = const Color(0xFF0A0C16),
    this.syntaxHighlightColor = const Color(0xFF60A5FA),
    this.brandGradient = const LinearGradient(
      colors: [Color(0xFF1337EC), Color(0xFF8B5CF6)],
    ),
    this.synKeyword = const Color(0xFF60A5FA),
    this.synSubject = const Color(0xFF38BDF8),
    this.synNumber = const Color(0xFFFBBF24),
    this.synComment = const Color(0xFF6B7280),
    this.synString = const Color(0xFF34D399),
    this.nodeEnsemble = const Color(0xFF3B82F6),
    this.nodeMotor = const Color(0xFFF59E0B),
    this.nodeInterneuron = const Color(0xFF14B8A6),
    this.nodeGenericEnsemble = const Color(0xFF60A5FA),
    this.nodeInput = const Color(0xFF22C55E),
    this.nodeErrorInput = const Color(0xFFEF4444),
    this.edgeExcitatory = const Color(0xFF3B82F6),
    this.edgeInhibitory = const Color(0xFFEF4444),
    this.edgePlastic = const Color(0xFFF59E0B),
    this.variant = NmtkThemeVariant.defaultNavy,
  });

  factory NmtkShellTokens.fromColorScheme(
    ColorScheme colorScheme,
    Brightness brightness,
  ) {
    final isDark = brightness == Brightness.dark;
    final commandAccentContainer = colorScheme.primaryContainer;
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
        accentContainer: commandAccentContainer,
        accentForeground: nmtkReadableForeground(
          colorScheme.onPrimaryContainer,
          commandAccentContainer,
        ),
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
    // Material path: legacy widgets still pump tokens through
    // ThemeData.extensions. This branch goes away at Task 6 of
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
    Color? terminalBackground,
    Color? syntaxHighlightColor,
    LinearGradient? brandGradient,
    Color? synKeyword,
    Color? synSubject,
    Color? synNumber,
    Color? synComment,
    Color? synString,
    Color? nodeEnsemble,
    Color? nodeMotor,
    Color? nodeInterneuron,
    Color? nodeGenericEnsemble,
    Color? nodeInput,
    Color? nodeErrorInput,
    Color? edgeExcitatory,
    Color? edgeInhibitory,
    Color? edgePlastic,
    NmtkThemeVariant? variant,
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
      terminalBackground: terminalBackground ?? this.terminalBackground,
      syntaxHighlightColor: syntaxHighlightColor ?? this.syntaxHighlightColor,
      brandGradient: brandGradient ?? this.brandGradient,
      synKeyword: synKeyword ?? this.synKeyword,
      synSubject: synSubject ?? this.synSubject,
      synNumber: synNumber ?? this.synNumber,
      synComment: synComment ?? this.synComment,
      synString: synString ?? this.synString,
      nodeEnsemble: nodeEnsemble ?? this.nodeEnsemble,
      nodeMotor: nodeMotor ?? this.nodeMotor,
      nodeInterneuron: nodeInterneuron ?? this.nodeInterneuron,
      nodeGenericEnsemble: nodeGenericEnsemble ?? this.nodeGenericEnsemble,
      nodeInput: nodeInput ?? this.nodeInput,
      nodeErrorInput: nodeErrorInput ?? this.nodeErrorInput,
      edgeExcitatory: edgeExcitatory ?? this.edgeExcitatory,
      edgeInhibitory: edgeInhibitory ?? this.edgeInhibitory,
      edgePlastic: edgePlastic ?? this.edgePlastic,
      variant: variant ?? this.variant,
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
      terminalBackground: Color.lerp(
        terminalBackground,
        other.terminalBackground,
        t,
      )!,
      syntaxHighlightColor: Color.lerp(
        syntaxHighlightColor,
        other.syntaxHighlightColor,
        t,
      )!,
      brandGradient: LinearGradient.lerp(
        brandGradient,
        other.brandGradient,
        t,
      )!,
      synKeyword: Color.lerp(synKeyword, other.synKeyword, t)!,
      synSubject: Color.lerp(synSubject, other.synSubject, t)!,
      synNumber: Color.lerp(synNumber, other.synNumber, t)!,
      synComment: Color.lerp(synComment, other.synComment, t)!,
      synString: Color.lerp(synString, other.synString, t)!,
      nodeEnsemble: Color.lerp(nodeEnsemble, other.nodeEnsemble, t)!,
      nodeMotor: Color.lerp(nodeMotor, other.nodeMotor, t)!,
      nodeInterneuron: Color.lerp(nodeInterneuron, other.nodeInterneuron, t)!,
      nodeGenericEnsemble: Color.lerp(
        nodeGenericEnsemble,
        other.nodeGenericEnsemble,
        t,
      )!,
      nodeInput: Color.lerp(nodeInput, other.nodeInput, t)!,
      nodeErrorInput: Color.lerp(nodeErrorInput, other.nodeErrorInput, t)!,
      edgeExcitatory: Color.lerp(edgeExcitatory, other.edgeExcitatory, t)!,
      edgeInhibitory: Color.lerp(edgeInhibitory, other.edgeInhibitory, t)!,
      edgePlastic: Color.lerp(edgePlastic, other.edgePlastic, t)!,
      variant: t < 0.5 ? variant : other.variant,
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

extension NmtkThemeExtensions on BuildContext {
  NmtkShellTokens get nmtkTokens => NmtkShellTokens.of(this);
}
