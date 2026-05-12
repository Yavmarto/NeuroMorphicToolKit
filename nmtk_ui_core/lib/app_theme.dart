import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/models/shell_models.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/widgets/top_app_bar.dart';

/// ----------------------------------------------------------------------------
/// NMTK BRAND TOKENS & EXPRESSIVE SHAPES
/// ----------------------------------------------------------------------------

class NmtkDesignTokens {
  static const Color primarySeed = Color(0xFF38BDF8); // Sky Blue
  static const Color backgroundLight = Color(0xFFF8FAFC); // Slate-50
  static const Color backgroundDark = Color(0xFF08090A); // Midnight
  static const Color surfaceDark = Color(0xFF111827); // Deep Navy

  static final BorderRadius buttonShape = BorderRadius.circular(12.0);
  static final BorderRadius cardShape = BorderRadius.circular(16.0);
  static final BorderRadius dialogShape = BorderRadius.circular(20.0);
  static final BorderRadius inputShape = BorderRadius.circular(8.0);
}

class NmtkFontFamilies {
  NmtkFontFamilies._();

  static const String package = 'nmtk_ui_core';
  static const String ui = 'Space Grotesk';
  static const String monospace = 'JetBrains Mono';
}

/// ----------------------------------------------------------------------------
/// NEUROCNL MODULE TOKENS
/// ----------------------------------------------------------------------------

class NmtkNeurocnlTokens {
  NmtkNeurocnlTokens._();

  static const Color background = Color(0xFF08090A);
  static const Color surface = Color(0xFF0F172A);
  static const Color surfaceVariant = Color(0xFF1E293B);

  static const Color primary = Color(0xFF38BDF8);
  static const Color primaryDim = Color(0xFF0EA5E9);

  /// CNL **syntax-diagnostic colours only** (Dracula-derived palette).
  ///
  /// These colours are used exclusively by:
  ///   - CNL editor syntax highlighting (`synKeyword`, `synSubject`, etc.)
  ///   - CNL compiler diagnostic overlays shown inside the editor pane
  ///   - Node/edge colour vocabulary in the network graph canvas
  ///
  /// For any module-level status UI — run buttons, pipeline step states,
  /// health badges, toast notifications, status strips — use the shared
  /// semantic palette from [NmtkShellTokens] instead:
  ///   - [NmtkShellTokens.healthyColor]  for success / healthy state
  ///   - [NmtkShellTokens.errorColor]    for error / failure state
  ///   - [NmtkShellTokens.warningColor]  for warning / caution state
  ///   - [NmtkShellTokens.runningColor]  for active / in-progress state
  static const Color success = Color(0xFF4ADE80);
  static const Color error = Color(0xFFFF5C7A);
  static const Color warning = Color(0xFFFFB347);
  static const Color info = Color(0xFF60A5FA);

  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color border = Color(0xFF1E293B);

  static const Color synKeyword = Color(0xFF818CF8); // Indigo-400 (Distinguished from Graph Blue)
  static const Color synSubject = Color(0xFFF1F5F9); // White
  static const Color synNumber = Color(0xFF22D3EE); // Cyan
  static const Color synVerb = Color(0xFF34D399); // Emerald (Action/Relation)
  static const Color synUnit = Color(0xFF94A3B8); // Slate (Units/Measurement)
  static const Color synComment = Color(0xFF64748B); // Slate
  static const Color synString = Color(0xFFA3E635); // Lime

  static const Color nodeEnsemble = Color(0xFF38BDF8); // Sky-400
  static const Color nodeMotor = Color(0xFF38BDF8); // Sky-400
  static const Color nodeInterneuron = Color(0xFF34D399); // Emerald-400
  static const Color nodeGenericEnsemble = Color(0xFF38BDF8);
  static const Color nodeInput = Color(0xFF34D399);
  static const Color nodeErrorInput = Color(0xFFEF4444);

  static const Color edgeExcitatory = Color(0xFF38BDF8);
  static const Color edgeInhibitory = Color(0xFFEF4444);
  static const Color edgePlastic = Color(0xFF22D3EE);
}

/// ----------------------------------------------------------------------------
/// THEME VARIANTS
/// ----------------------------------------------------------------------------

enum NmtkThemeVariant {
  defaultNavy,
  neurocnl,
  neurohub,
  neurochip,
  neurobench,
  neurosim,
  neurosense,
}

/// ----------------------------------------------------------------------------
/// CUSTOM THEME EXTENSION
/// ----------------------------------------------------------------------------

class NmtkThemeExtension extends ThemeExtension<NmtkThemeExtension> {
  // Base
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

  const NmtkThemeExtension({
    required this.terminalBackground,
    required this.syntaxHighlightColor,
    required this.brandGradient,
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

  @override
  ThemeExtension<NmtkThemeExtension> copyWith({
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
    return NmtkThemeExtension(
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
  ThemeExtension<NmtkThemeExtension> lerp(
    covariant ThemeExtension<NmtkThemeExtension>? other,
    double t,
  ) {
    if (other is! NmtkThemeExtension) {
      return this;
    }

    return NmtkThemeExtension(
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
}

Color _seedForVariant(NmtkThemeVariant variant) {
  switch (variant) {
    case NmtkThemeVariant.defaultNavy:
      return NmtkDesignTokens.primarySeed;
    case NmtkThemeVariant.neurocnl:
      return NmtkNeurocnlTokens.primary;
    case NmtkThemeVariant.neurohub:
      return const Color(0xFF0D9488);
    case NmtkThemeVariant.neurochip:
      return const Color(0xFF0891B2);
    case NmtkThemeVariant.neurobench:
      return const Color(0xFF16A34A);
    case NmtkThemeVariant.neurosim:
      return const Color(0xFF4338CA);
    case NmtkThemeVariant.neurosense:
      return const Color(0xFFE11D48);
  }
}

/// ----------------------------------------------------------------------------
/// APP THEME CONFIGURATION
/// ----------------------------------------------------------------------------

class AppTheme {
  AppTheme._();

  static TextTheme _buildTextTheme(TextTheme base) {
    return base.apply(
      fontFamily: NmtkFontFamilies.ui,
      package: NmtkFontFamilies.package,
      displayColor: base.titleLarge?.color,
      bodyColor: base.bodyLarge?.color,
    );
  }

  static ThemeData get lightTheme =>
      lightThemeForVariant(NmtkThemeVariant.defaultNavy);

  static ThemeData get darkTheme =>
      darkThemeForVariant(NmtkThemeVariant.defaultNavy);

  static ThemeData lightThemeForVariant(NmtkThemeVariant variant) {
    if (variant == NmtkThemeVariant.neurocnl) {
      return _neurocnlLightTheme();
    }
    return _suiteLightTheme(variant);
  }

  static ThemeData darkThemeForVariant(NmtkThemeVariant variant) {
    if (variant == NmtkThemeVariant.neurocnl) {
      return _neurocnlDarkTheme();
    }
    return _suiteDarkTheme(variant);
  }

  static ThemeData _suiteLightTheme(NmtkThemeVariant variant) {
    final seed = _seedForVariant(variant);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: NmtkDesignTokens.backgroundLight,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: NmtkDesignTokens.backgroundLight,
      textTheme: _buildTextTheme(ThemeData.light().textTheme),
      extensions: [
        _suiteExtension(colorScheme, Brightness.light, variant),
        NmtkShellTokens.fromColorScheme(colorScheme, Brightness.light),
      ],
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(borderRadius: NmtkDesignTokens.cardShape),
        elevation: 0,
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: NmtkDesignTokens.buttonShape,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          minimumSize: const Size(48, 48),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  static ThemeData _suiteDarkTheme(NmtkThemeVariant variant) {
    final seed = _seedForVariant(variant);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      surface: NmtkDesignTokens.backgroundDark,
      onSurface: const Color(0xFFF1F5F9),
      surfaceContainerLowest: const Color(0xFF020617),
      surfaceContainerLow: const Color(0xFF0F172A),
      surfaceContainer: const Color(0xFF111827),
      surfaceContainerHigh: const Color(0xFF1E293B),
      surfaceContainerHighest: NmtkDesignTokens.surfaceDark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: NmtkDesignTokens.backgroundDark,
      textTheme: _buildTextTheme(ThemeData.dark().textTheme),
      extensions: [
        _suiteExtension(colorScheme, Brightness.dark, variant),
        NmtkShellTokens.fromColorScheme(colorScheme, Brightness.dark),
      ],
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: NmtkDesignTokens.cardShape,
          side: const BorderSide(color: Color(0xFF1E293B), width: 1),
        ),
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: NmtkDesignTokens.buttonShape,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          minimumSize: const Size(48, 48),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: NmtkDesignTokens.surfaceDark,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  static NmtkThemeExtension _suiteExtension(
    ColorScheme colorScheme,
    Brightness brightness,
    NmtkThemeVariant variant,
  ) {
    final isDark = brightness == Brightness.dark;
    return NmtkThemeExtension(
      terminalBackground: isDark
          ? const Color(0xFF0A0C16)
          : const Color(0xFFE2E8F0),
      syntaxHighlightColor: colorScheme.primary,
      brandGradient: LinearGradient(
        colors: isDark
            ? [colorScheme.primary, colorScheme.secondaryContainer]
            : [colorScheme.primary, colorScheme.tertiary],
      ),
      synKeyword: isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8),
      synSubject: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
      synNumber: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
      synComment: isDark ? const Color(0xFF6B7280) : const Color(0xFF4B5563),
      synString: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
      nodeEnsemble: isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB),
      nodeMotor: isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706),
      nodeInterneuron: isDark
          ? const Color(0xFF14B8A6)
          : const Color(0xFF0D9488),
      nodeInput: isDark ? const Color(0xFF22C55E) : const Color(0xFF16A34A),
      nodeErrorInput: isDark
          ? const Color(0xFFEF4444)
          : const Color(0xFFDC2626),
      edgeExcitatory: isDark
          ? const Color(0xFF3B82F6)
          : const Color(0xFF2563EB),
      edgeInhibitory: isDark
          ? const Color(0xFFEF4444)
          : const Color(0xFFDC2626),
      edgePlastic: isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706),
      variant: variant,
    );
  }

  static ThemeData _neurocnlDarkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: NmtkNeurocnlTokens.primary,
      brightness: Brightness.dark,
      surface: NmtkNeurocnlTokens.surface,
      onSurface: NmtkNeurocnlTokens.textPrimary,
      surfaceContainerHighest: NmtkNeurocnlTokens.surfaceVariant,
      error: NmtkNeurocnlTokens.error,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: NmtkNeurocnlTokens.background,
      textTheme: _buildTextTheme(ThemeData.dark().textTheme),
      extensions: [
        _neurocnlExtension(Brightness.dark, colorScheme),
        NmtkShellTokens.fromColorScheme(colorScheme, Brightness.dark),
      ],
      cardTheme: CardThemeData(
        color: NmtkNeurocnlTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: NmtkDesignTokens.cardShape,
          side: const BorderSide(color: NmtkNeurocnlTokens.border),
        ),
        elevation: 0,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: NmtkNeurocnlTokens.surface,
        foregroundColor: NmtkNeurocnlTokens.textPrimary,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: NmtkFontFamilies.ui,
          package: NmtkFontFamilies.package,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: NmtkNeurocnlTokens.textPrimary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NmtkNeurocnlTokens.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: NmtkDesignTokens.buttonShape,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          minimumSize: const Size(48, 48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NmtkNeurocnlTokens.primary,
          side: const BorderSide(color: NmtkNeurocnlTokens.primary),
          shape: RoundedRectangleBorder(
            borderRadius: NmtkDesignTokens.buttonShape,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NmtkNeurocnlTokens.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: NmtkDesignTokens.inputShape,
          borderSide: const BorderSide(color: NmtkNeurocnlTokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: NmtkDesignTokens.inputShape,
          borderSide: const BorderSide(color: NmtkNeurocnlTokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: NmtkDesignTokens.inputShape,
          borderSide: const BorderSide(
            color: NmtkNeurocnlTokens.primary,
            width: 2,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: NmtkNeurocnlTokens.border,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: NmtkNeurocnlTokens.surfaceVariant,
        labelStyle: const TextStyle(
          fontFamily: NmtkFontFamilies.ui,
          package: NmtkFontFamilies.package,
          fontSize: 12,
          color: NmtkNeurocnlTokens.textSecondary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: NmtkNeurocnlTokens.border),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: NmtkNeurocnlTokens.primary,
        unselectedLabelColor: NmtkNeurocnlTokens.textSecondary,
        indicatorColor: NmtkNeurocnlTokens.primary,
        dividerColor: NmtkNeurocnlTokens.border,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: NmtkNeurocnlTokens.surface,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  static ThemeData _neurocnlLightTheme() {
    const background = Color(0xFFF2F2F2);
    const surface = Color(0xFFFFFFFF);
    const surfaceVariant = Color(0xFFE5E7EB);
    const border = Color(0xFFD1D5DB);
    const textPrimary = Color(0xFF18181B);
    const textSecondary = Color(0xFF52525B);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: NmtkNeurocnlTokens.primary,
      brightness: Brightness.light,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceVariant,
      error: NmtkNeurocnlTokens.error,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      textTheme: _buildTextTheme(ThemeData.light().textTheme),
      extensions: [
        _neurocnlExtension(Brightness.light, colorScheme),
        NmtkShellTokens.fromColorScheme(colorScheme, Brightness.light),
      ],
      cardTheme: CardThemeData(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: NmtkDesignTokens.cardShape,
          side: const BorderSide(color: border),
        ),
        elevation: 0,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: NmtkFontFamilies.ui,
          package: NmtkFontFamilies.package,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NmtkNeurocnlTokens.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: NmtkDesignTokens.buttonShape,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          minimumSize: const Size(48, 48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NmtkNeurocnlTokens.primaryDim,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: NmtkDesignTokens.buttonShape,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: NmtkDesignTokens.inputShape,
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: NmtkDesignTokens.inputShape,
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: NmtkDesignTokens.inputShape,
          borderSide: const BorderSide(
            color: NmtkNeurocnlTokens.primary,
            width: 2,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceVariant,
        labelStyle: const TextStyle(
          fontFamily: NmtkFontFamilies.ui,
          package: NmtkFontFamilies.package,
          fontSize: 12,
          color: textSecondary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: border),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: NmtkNeurocnlTokens.primaryDim,
        unselectedLabelColor: textSecondary,
        indicatorColor: NmtkNeurocnlTokens.primary,
        dividerColor: border,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  static NmtkThemeExtension _neurocnlExtension(
    Brightness brightness,
    ColorScheme colorScheme,
  ) {
    final isDark = brightness == Brightness.dark;
    return NmtkThemeExtension(
      terminalBackground: isDark
          ? NmtkNeurocnlTokens.background
          : const Color(0xFFF5F1FF),
      syntaxHighlightColor: NmtkNeurocnlTokens.synKeyword,
      brandGradient: LinearGradient(
        colors: [colorScheme.primary, colorScheme.secondary],
      ),
      synKeyword: NmtkNeurocnlTokens.synKeyword,
      synSubject: NmtkNeurocnlTokens.synSubject,
      synNumber: NmtkNeurocnlTokens.synNumber,
      synComment: NmtkNeurocnlTokens.synComment,
      synString: NmtkNeurocnlTokens.synString,
      nodeEnsemble: NmtkNeurocnlTokens.nodeEnsemble,
      nodeMotor: NmtkNeurocnlTokens.nodeMotor,
      nodeInterneuron: NmtkNeurocnlTokens.nodeInterneuron,
      nodeGenericEnsemble: NmtkNeurocnlTokens.nodeGenericEnsemble,
      nodeInput: NmtkNeurocnlTokens.nodeInput,
      nodeErrorInput: NmtkNeurocnlTokens.nodeErrorInput,
      edgeExcitatory: NmtkNeurocnlTokens.edgeExcitatory,
      edgeInhibitory: NmtkNeurocnlTokens.edgeInhibitory,
      edgePlastic: NmtkNeurocnlTokens.edgePlastic,
      variant: NmtkThemeVariant.neurocnl,
    );
  }

  static ThemeData get highContrastLightTheme {
    final base = _suiteLightTheme(NmtkThemeVariant.defaultNavy);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: Colors.blue.shade900,
        secondary: Colors.blue.shade900,
        surface: Colors.white,
        onSurface: Colors.black,
        outline: Colors.black,
      ),
      visualDensity: VisualDensity.comfortable,
    );
  }

  static ThemeData get highContrastDarkTheme {
    final base = _suiteDarkTheme(NmtkThemeVariant.defaultNavy);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: Colors.yellowAccent,
        secondary: Colors.yellowAccent,
        surface: Colors.black,
        onSurface: Colors.white,
        outline: Colors.white,
      ),
      visualDensity: VisualDensity.comfortable,
    );
  }
}

/// ----------------------------------------------------------------------------
/// ADAPTIVE LAYOUT
/// ----------------------------------------------------------------------------

class ResponsiveScaffold extends StatelessWidget {
  final Widget body;
  final int currentIndex;
  final ValueChanged<int> onNavigationTargetSelected;
  final List<NavigationDestinationData> destinations;
  final Widget? floatingActionButton;
  final List<NmtkTopAppBarAction> appBarActions;

  const ResponsiveScaffold({
    super.key,
    required this.body,
    required this.currentIndex,
    required this.onNavigationTargetSelected,
    required this.destinations,
    this.floatingActionButton,
    this.appBarActions = const <NmtkTopAppBarAction>[],
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;

        if (screenWidth < 600) {
          return Scaffold(
            body: body,
            floatingActionButton: floatingActionButton,
            bottomNavigationBar: NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: onNavigationTargetSelected,
              destinations: destinations.map((destination) {
                return NavigationDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(
                    destination.selectedIcon ?? destination.icon,
                  ),
                  label: destination.label,
                );
              }).toList(),
            ),
          );
        }

        return Scaffold(
          appBar: NmtkTopAppBar(
            leading: Container(
              key: const ValueKey('responsive-topnav-brand'),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.memory,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: const Text('NMTK Hub'),
            destinations: destinations,
            selectedIndex: currentIndex,
            onDestinationSelected: onNavigationTargetSelected,
            actions: appBarActions,
          ),
          floatingActionButton: floatingActionButton,
          body: body,
        );
      },
    );
  }
}

/// ----------------------------------------------------------------------------
/// NAVIGATION ITEM DATACLASS
/// ----------------------------------------------------------------------------

class NavigationDestinationData {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;

  const NavigationDestinationData({
    required this.icon,
    this.selectedIcon,
    required this.label,
  });
}
