import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nmtk_ui_core/widgets/nmtk_navigation_rail.dart';

/// ----------------------------------------------------------------------------
/// NMTK BRAND TOKENS & EXPRESSIVE SHAPES
/// ----------------------------------------------------------------------------

class NmtkDesignTokens {
  static const Color primarySeed = Color(0xFF1337EC);
  static const Color backgroundLight = Color(0xFFF6F6F8);
  static const Color backgroundDark = Color(0xFF101322);
  static const Color surfaceDark = Color(0xFF0D101D);

  static final BorderRadius buttonShape = BorderRadius.circular(16.0);
  static final BorderRadius cardShape = BorderRadius.circular(24.0);
  static final BorderRadius dialogShape = BorderRadius.circular(28.0);
  static final BorderRadius inputShape = BorderRadius.circular(12.0);
}

/// ----------------------------------------------------------------------------
/// NEUROCNL MODULE TOKENS
/// ----------------------------------------------------------------------------

class NmtkNeurocnlTokens {
  NmtkNeurocnlTokens._();

  static const Color background = Color(0xFF0F0D1A);
  static const Color surface = Color(0xFF1A1625);
  static const Color surfaceVariant = Color(0xFF231E35);

  static const Color primary = Color(0xFF9B7FFF);
  static const Color primaryDim = Color(0xFF7B5FDF);

  static const Color success = Color(0xFF4ADE80);
  static const Color error = Color(0xFFFF5C7A);
  static const Color warning = Color(0xFFFFB347);
  static const Color info = Color(0xFF60A5FA);

  static const Color textPrimary = Color(0xFFF1EEF9);
  static const Color textSecondary = Color(0xFFB0A8CC);
  static const Color border = Color(0xFF3D3560);

  static const Color synKeyword = Color(0xFFBD93F9);
  static const Color synSubject = Color(0xFF8BE9FD);
  static const Color synNumber = Color(0xFFFFB86C);
  static const Color synComment = Color(0xFF6272A4);
  static const Color synString = Color(0xFFF1FA8C);

  static const Color nodeEnsemble = Color(0xFF9B7FFF);
  static const Color nodeMotor = Color(0xFFFFB86C);
  static const Color nodeInterneuron = Color(0xFF50D0B0);
  static const Color nodeGenericEnsemble = Color(0xFFBD93F9);
  static const Color nodeInput = Color(0xFF50FA7B);
  static const Color nodeErrorInput = Color(0xFFFF6E6E);

  static const Color edgeExcitatory = Color(0xFF8BE9FD);
  static const Color edgeInhibitory = Color(0xFFFF5555);
  static const Color edgePlastic = Color(0xFFFFD700);
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
  final Color glassmorphismColor;

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
    required this.glassmorphismColor,
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
    Color? glassmorphismColor,
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
      glassmorphismColor: glassmorphismColor ?? this.glassmorphismColor,
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
      glassmorphismColor: Color.lerp(
        glassmorphismColor,
        other.glassmorphismColor,
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
      return const Color(0xFFD97706);
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
      fontFamily: 'Space Grotesk',
      displayColor: base.titleLarge?.color,
      bodyColor: base.bodyLarge?.color,
    );
  }

  static TextTheme _buildInterTextTheme(TextTheme base) {
    return GoogleFonts.interTextTheme(base);
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
      extensions: [_suiteExtension(colorScheme, Brightness.light, variant)],
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
      surfaceContainerLowest: const Color(0xFF0A0D1A),
      surfaceContainerLow: const Color(0xFF0F1220),
      surfaceContainer: const Color(0xFF141728),
      surfaceContainerHigh: const Color(0xFF1A1E30),
      surfaceContainerHighest: NmtkDesignTokens.surfaceDark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: NmtkDesignTokens.backgroundDark,
      textTheme: _buildTextTheme(ThemeData.dark().textTheme),
      extensions: [_suiteExtension(colorScheme, Brightness.dark, variant)],
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
      glassmorphismColor: isDark
          ? NmtkDesignTokens.backgroundDark.withValues(alpha: 0.8)
          : Colors.white.withValues(alpha: 0.7),
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
      textTheme: _buildInterTextTheme(ThemeData.dark().textTheme),
      extensions: [_neurocnlExtension(Brightness.dark, colorScheme)],
      cardTheme: CardThemeData(
        color: NmtkNeurocnlTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: NmtkDesignTokens.cardShape,
          side: const BorderSide(color: NmtkNeurocnlTokens.border),
        ),
        elevation: 0,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: NmtkNeurocnlTokens.surface,
        foregroundColor: NmtkNeurocnlTokens.textPrimary,
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(
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
        labelStyle: GoogleFonts.inter(
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
    const background = Color(0xFFF8F6FF);
    const surface = Color(0xFFFFFFFF);
    const surfaceVariant = Color(0xFFEAE3FF);
    const border = Color(0xFFD8CCFF);
    const textPrimary = Color(0xFF261F39);
    const textSecondary = Color(0xFF5D557A);

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
      textTheme: _buildInterTextTheme(ThemeData.light().textTheme),
      extensions: [_neurocnlExtension(Brightness.light, colorScheme)],
      cardTheme: CardThemeData(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: NmtkDesignTokens.cardShape,
          side: const BorderSide(color: border),
        ),
        elevation: 0,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(
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
        labelStyle: GoogleFonts.inter(fontSize: 12, color: textSecondary),
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
      glassmorphismColor: isDark
          ? const Color(0xCC1A1625)
          : const Color(0xCCFFFFFF),
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

class ResponsiveScaffold extends StatefulWidget {
  final Widget body;
  final int currentIndex;
  final ValueChanged<int> onNavigationTargetSelected;
  final List<NavigationDestinationData> destinations;
  final Widget? floatingActionButton;

  const ResponsiveScaffold({
    super.key,
    required this.body,
    required this.currentIndex,
    required this.onNavigationTargetSelected,
    required this.destinations,
    this.floatingActionButton,
  });

  @override
  State<ResponsiveScaffold> createState() => _ResponsiveScaffoldState();
}

class _ResponsiveScaffoldState extends State<ResponsiveScaffold> {
  static const double _expandedSidebarWidth = 256;
  static const double _collapsedSidebarWidth = 88;

  bool _isSidebarCollapsed = false;

  bool get _isDesktopContext {
    if (kIsWeb) {
      return true;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;

        if (screenWidth < 600) {
          return Scaffold(
            body: widget.body,
            floatingActionButton: widget.floatingActionButton,
            bottomNavigationBar: NavigationBar(
              selectedIndex: widget.currentIndex,
              onDestinationSelected: widget.onNavigationTargetSelected,
              destinations: widget.destinations.map((destination) {
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

        if (screenWidth < 1240) {
          return Scaffold(
            floatingActionButton: widget.floatingActionButton,
            body: Row(
              children: [
                NmtkNavigationRail(
                  selectedIndex: widget.currentIndex,
                  onDestinationSelected: widget.onNavigationTargetSelected,
                  destinations: widget.destinations,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.memory,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: widget.body),
              ],
            ),
          );
        }

        return Scaffold(
          floatingActionButton: widget.floatingActionButton,
          body: Row(
            children: [
              Container(
                key: const ValueKey('responsive-desktop-sidebar'),
                width: _isSidebarCollapsed
                    ? _collapsedSidebarWidth
                    : _expandedSidebarWidth,
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  children: [
                    _buildDesktopBrandHeader(),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                        itemCount: widget.destinations.length,
                        itemBuilder: (context, index) {
                          final isSelected = widget.currentIndex == index;
                          final destination = widget.destinations[index];

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Tooltip(
                              message: destination.label,
                              waitDuration: const Duration(milliseconds: 300),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: NmtkDesignTokens.buttonShape,
                                child: InkWell(
                                  borderRadius: NmtkDesignTokens.buttonShape,
                                  hoverColor: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.08),
                                  onTap: () =>
                                      widget.onNavigationTargetSelected(index),
                                  child: Container(
                                    padding: _isSidebarCollapsed
                                        ? const EdgeInsets.symmetric(
                                            vertical: 12,
                                          )
                                        : const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
                                                .withValues(
                                                  alpha: _isDesktopContext
                                                      ? 0.8
                                                      : 1,
                                                )
                                          : Colors.transparent,
                                      borderRadius:
                                          NmtkDesignTokens.buttonShape,
                                    ),
                                    child: _isSidebarCollapsed
                                        ? Center(
                                            child: Icon(
                                              isSelected
                                                  ? (destination.selectedIcon ??
                                                        destination.icon)
                                                  : destination.icon,
                                              color: isSelected
                                                  ? Theme.of(context)
                                                        .colorScheme
                                                        .onPrimaryContainer
                                                  : Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                            ),
                                          )
                                        : Row(
                                            children: [
                                              Icon(
                                                isSelected
                                                    ? (destination
                                                              .selectedIcon ??
                                                          destination.icon)
                                                    : destination.icon,
                                                color: isSelected
                                                    ? Theme.of(context)
                                                          .colorScheme
                                                          .onPrimaryContainer
                                                    : Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                              ),
                                              const SizedBox(width: 16),
                                              Flexible(
                                                child: Text(
                                                  destination.label,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: isSelected
                                                        ? FontWeight.w600
                                                        : FontWeight.w500,
                                                    color: isSelected
                                                        ? Theme.of(context)
                                                              .colorScheme
                                                              .onPrimaryContainer
                                                        : Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(child: widget.body),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesktopBrandHeader() {
    final toggleButton = IconButton(
      key: const ValueKey('responsive-sidebar-toggle'),
      tooltip: _isSidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar',
      onPressed: () {
        setState(() {
          _isSidebarCollapsed = !_isSidebarCollapsed;
        });
      },
      icon: Icon(
        _isSidebarCollapsed ? Icons.chevron_right : Icons.chevron_left,
      ),
    );

    if (_isSidebarCollapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.memory,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            toggleButton,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.memory,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          if (!_isSidebarCollapsed) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NMTK Hub',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Neuromorphic Toolkit',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
          toggleButton,
        ],
      ),
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
