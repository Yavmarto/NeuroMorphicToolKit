import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/models/shell_models.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/widgets/top_app_bar.dart';

/// ----------------------------------------------------------------------------
/// NMTK BRAND TOKENS & EXPRESSIVE SHAPES
/// ----------------------------------------------------------------------------

class NmtkDesignTokens {
  static const Color primarySeed = Color(0xFF1337EC); // Zebra Blue
  static const Color backgroundLight = Color(0xFFF6F6F8); // Slate tint light
  static const Color backgroundDark = Color(0xFF101322); // Midnight tint dark
  static const Color surfaceDark = Color(0xFF111827); // Deep Navy

  static final BorderRadius buttonShape = BorderRadius.circular(16.0);
  static final BorderRadius cardShape = BorderRadius.circular(24.0);
  static final BorderRadius dialogShape = BorderRadius.circular(20.0);
  static final BorderRadius inputShape = BorderRadius.circular(12.0);
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

  /// Restricted to CNL-editor syntax diagnostics and network-graph canvas
  /// elements only. For module-level status UI, use [NmtkShellTokens] instead.
  static const Color success = Color(0xFF4ADE80);

  /// Restricted to CNL-editor syntax diagnostics and network-graph canvas
  /// elements only. For module-level status UI, use [NmtkShellTokens] instead.
  static const Color error = Color(0xFFFF5C7A);

  /// Restricted to CNL-editor syntax diagnostics and network-graph canvas
  /// elements only. For module-level status UI, use [NmtkShellTokens] instead.
  static const Color warning = Color(0xFFFFB347);
  static const Color info = Color(0xFF60A5FA);

  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color border = Color(0xFF1E293B);

  static const Color synKeyword = Color(
    0xFF818CF8,
  ); // Indigo-400 (Distinguished from Graph Blue)
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
      return const Color(
        0xFF8B5CF6,
      ); // Studio Violet (NmtkShellTokens.dark.studioPalette.accent)
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
      seedColor: const Color(
        0xFF8B5CF6,
      ), // NmtkShellTokens.dark.studioPalette.accent
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
    );
  }

  static ThemeData _neurocnlLightTheme() {
    const background = Color(0xFFF2F2F2);
    const surface = Color(0xFFFFFFFF);
    const surfaceVariant = Color(0xFFE5E7EB);

    const textPrimary = Color(0xFF18181B);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(
        0xFF7C3AED,
      ), // NmtkShellTokens.light.studioPalette.accent
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
        primary: const Color(0xFF0D47A1),
        secondary: const Color(0xFF0D47A1),
        surface: const Color(0xFFFFFFFF),
        onSurface: const Color(0xFF000000),
        outline: const Color(0xFF000000),
      ),
      visualDensity: VisualDensity.comfortable,
    );
  }

  static ThemeData get highContrastDarkTheme {
    final base = _suiteDarkTheme(NmtkThemeVariant.defaultNavy);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: const Color(0xFFFFFF00),
        secondary: const Color(0xFFFFFF00),
        surface: const Color(0xFF000000),
        onSurface: const Color(0xFFFFFFFF),
        outline: const Color(0xFFFFFFFF),
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
                ZetaIcons.memory,
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
