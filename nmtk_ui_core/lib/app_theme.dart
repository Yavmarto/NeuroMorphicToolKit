import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/widgets/nmtk_navigation_rail.dart';

/// ----------------------------------------------------------------------------
/// NMTK BRAND TOKENS & EXPRESSIVE SHAPES
/// ----------------------------------------------------------------------------

class NmtkDesignTokens {
  // Brand Colors mapped from your HTML snippets
  static const Color primarySeed = Color(0xFF1337EC); // NMTK Primary
  static const Color backgroundLight = Color(0xFFF6F6F8);
  static const Color backgroundDark = Color(0xFF101322); // Deep navy space
  static const Color surfaceDark = Color(0xFF0D101D); // Editor pane background

  // Expressive Shape Morphing Tokens (2026 M3 Guidelines)
  static final BorderRadius buttonShape = BorderRadius.circular(16.0);
  static final BorderRadius cardShape = BorderRadius.circular(24.0);
  static final BorderRadius dialogShape = BorderRadius.circular(28.0);
}

/// ----------------------------------------------------------------------------
/// CUSTOM THEME EXTENSION (Brand-specific gradients & glassmorphism)
/// ----------------------------------------------------------------------------

class NmtkThemeExtension extends ThemeExtension<NmtkThemeExtension> {
  final Color terminalBackground;
  final Color syntaxHighlightColor;
  final LinearGradient brandGradient;
  final Color glassmorphismColor;

  const NmtkThemeExtension({
    required this.terminalBackground,
    required this.syntaxHighlightColor,
    required this.brandGradient,
    required this.glassmorphismColor,
  });

  @override
  ThemeExtension<NmtkThemeExtension> copyWith({
    Color? terminalBackground,
    Color? syntaxHighlightColor,
    LinearGradient? brandGradient,
    Color? glassmorphismColor,
  }) {
    return NmtkThemeExtension(
      terminalBackground: terminalBackground ?? this.terminalBackground,
      syntaxHighlightColor: syntaxHighlightColor ?? this.syntaxHighlightColor,
      brandGradient: brandGradient ?? this.brandGradient,
      glassmorphismColor: glassmorphismColor ?? this.glassmorphismColor,
    );
  }

  @override
  ThemeExtension<NmtkThemeExtension> lerp(
    ThemeExtension<NmtkThemeExtension>? other,
    double t,
  ) {
    if (other is! NmtkThemeExtension) return this;
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
    );
  }
}

/// ----------------------------------------------------------------------------
/// MODULE THEME VARIANTS
/// ----------------------------------------------------------------------------

/// Identifies which NMTK sub-module is requesting a themed [ThemeData].
///
/// Each variant maps to a distinct seed colour while sharing the same
/// Material 3 design-system structure, giving the suite a unified look
/// (similar to how Microsoft Office or Apple's app suite feels cohesive yet
/// each app has its own accent identity).
enum NmtkThemeVariant {
  /// Default NMTK navy/blue identity (same as the root [AppTheme]).
  nmtk,

  /// neurocnl Studio — purple / lavender identity.
  neurocnl,

  /// Neurohub — teal / cyan identity.
  neurohub,

  /// Neurochip — amber / gold identity.
  neurochip,

  /// Neurobench — green / emerald identity.
  neurobench,

  /// Neurosim — indigo / deep-blue identity.
  neurosim,

  /// Neurosense — rose / coral identity.
  neurosense,
}

/// ----------------------------------------------------------------------------
/// NEUROCNL COLOR TOKENS
/// ----------------------------------------------------------------------------

/// Design tokens for the **neurocnl Studio** module.
///
/// Uses a dark-mode-first purple / lavender palette.  All values are
/// `const` so they can be used in `static const` fields of other classes.
class NmtkNeurocnlTokens {
  NmtkNeurocnlTokens._();

  // ── Surface / Background ───────────────────────────────────────
  /// Deep purple-black page background.
  static const Color background = Color(0xFF0F0D1A);

  /// Dark purple card / panel surface.
  static const Color surface = Color(0xFF1A1625);

  /// Slightly elevated surface (e.g. input fields, hover states).
  static const Color surfaceVariant = Color(0xFF231E35);

  // ── Brand / Accent ─────────────────────────────────────────────
  /// Primary lavender accent.
  static const Color primary = Color(0xFF9B7FFF);

  /// Dimmed / secondary lavender (used for hover, disabled states).
  static const Color primaryDim = Color(0xFF7B5FDF);

  // ── Semantic ───────────────────────────────────────────────────
  /// Success green.
  static const Color success = Color(0xFF4ADE80);

  /// Error red-pink.
  static const Color error = Color(0xFFFF5C7A);

  /// Warning amber.
  static const Color warning = Color(0xFFFFB347);

  /// Info blue.
  static const Color info = Color(0xFF60A5FA);

  // ── Text ───────────────────────────────────────────────────────
  /// Primary text — near-white with a subtle purple tint.
  static const Color textPrimary = Color(0xFFF1EEF9);

  /// Secondary / muted text — soft lavender-grey.
  static const Color textSecondary = Color(0xFFB0A8CC);

  // ── Border ─────────────────────────────────────────────────────
  /// Subtle dark-purple border / divider.
  static const Color border = Color(0xFF3D3560);

  // ── Syntax Highlighting (CNL editor) ───────────────────────────
  /// Keywords (`connect`, `ensemble`, `input`, …).
  static const Color synKeyword = Color(0xFFBD93F9);

  /// Subject / identifier tokens.
  static const Color synSubject = Color(0xFF8BE9FD);

  /// Numeric literals.
  static const Color synNumber = Color(0xFFFFB86C);

  /// Comments.
  static const Color synComment = Color(0xFF6272A4);

  /// String literals.
  static const Color synString = Color(0xFFF1FA8C);

  // ── Graph Node / Edge colours ──────────────────────────────────
  /// Sensory ensemble node fill (default / fallback ensemble colour).
  static const Color nodeEnsemble = Color(0xFF9B7FFF);

  /// Motor ensemble node fill — warm amber.
  static const Color nodeMotor = Color(0xFFFFB86C);

  /// Interneuron ensemble node fill — teal.
  static const Color nodeInterneuron = Color(0xFF50D0B0);

  /// Generic / unknown ensemble node fill.
  static const Color nodeGenericEnsemble = Color(0xFFBD93F9);

  /// Input / stimulus node fill.
  static const Color nodeInput = Color(0xFF50FA7B);

  /// Error-signal input node fill — muted red-orange.
  static const Color nodeErrorInput = Color(0xFFFF6E6E);

  /// Excitatory synapse / edge stroke.
  static const Color edgeExcitatory = Color(0xFF8BE9FD);

  /// Inhibitory synapse / edge stroke.
  static const Color edgeInhibitory = Color(0xFFFF5555);

  /// Plastic (learning-rule) synapse / edge stroke — gold.
  static const Color edgePlastic = Color(0xFFFFD700);
}

/// ----------------------------------------------------------------------------
/// APP THEME CONFIGURATION
/// ----------------------------------------------------------------------------

/// Returns the seed colour associated with each [NmtkThemeVariant].
Color _seedForVariant(NmtkThemeVariant variant) {
  switch (variant) {
    case NmtkThemeVariant.nmtk:
      return NmtkDesignTokens.primarySeed; // navy/blue
    case NmtkThemeVariant.neurocnl:
      return const Color(0xFF7C5CBF); // purple
    case NmtkThemeVariant.neurohub:
      return const Color(0xFF0D9488); // teal
    case NmtkThemeVariant.neurochip:
      return const Color(0xFFD97706); // amber
    case NmtkThemeVariant.neurobench:
      return const Color(0xFF16A34A); // green
    case NmtkThemeVariant.neurosim:
      return const Color(0xFF4338CA); // indigo
    case NmtkThemeVariant.neurosense:
      return const Color(0xFFE11D48); // rose
  }
}

class AppTheme {
  // Shared M3 typography focusing on a modern grotesque/sans font
  static TextTheme _buildTextTheme(TextTheme base) {
    return base.apply(
      fontFamily: 'Space Grotesk', // Or 'Plus Jakarta Sans' / 'Inter'
      displayColor: base.titleLarge?.color,
      bodyColor: base.bodyLarge?.color,
    );
  }

  // Light Theme Configuration
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: NmtkDesignTokens.primarySeed,
      brightness: Brightness.light,
      surface: NmtkDesignTokens.backgroundLight,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: _buildTextTheme(ThemeData.light().textTheme),
      extensions: [
        NmtkThemeExtension(
          terminalBackground: const Color(0xFFE2E8F0),
          syntaxHighlightColor: NmtkDesignTokens.primarySeed,
          brandGradient: LinearGradient(
            colors: [colorScheme.primary, colorScheme.tertiary],
          ),
          glassmorphismColor: Colors.white.withValues(alpha: 0.7),
        ),
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
          minimumSize: const Size(48, 48), // Ensures 48dp modern touch targets
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // Dark Theme Configuration
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: NmtkDesignTokens.primarySeed,
      brightness: Brightness.dark,
      surface: NmtkDesignTokens.backgroundDark,
      // Expressive Color Roles overriden for NMTK dark mode identity
      onSurface: const Color(0xFFF1F5F9), // Slate 100
      surfaceContainerHighest: NmtkDesignTokens.surfaceDark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: NmtkDesignTokens.backgroundDark,
      textTheme: _buildTextTheme(ThemeData.dark().textTheme),
      extensions: [
        NmtkThemeExtension(
          terminalBackground: const Color(0xFF0A0C16),
          syntaxHighlightColor: const Color(0xFF60A5FA), // Blue 400
          brandGradient: LinearGradient(
            colors: [colorScheme.primary, colorScheme.secondaryContainer],
          ),
          glassmorphismColor: NmtkDesignTokens.backgroundDark.withValues(
            alpha: 0.8,
          ),
        ),
      ],
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: NmtkDesignTokens.cardShape,
          side: const BorderSide(
            color: Color(0xFF1E293B),
            width: 1,
          ), // Slate 800
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

  /// Returns a light [ThemeData] tuned for the given [NmtkThemeVariant].
  ///
  /// The variant's seed colour is used to generate the Material 3
  /// [ColorScheme], while all other design decisions (typography, shapes,
  /// component themes) remain consistent across the suite.
  static ThemeData lightThemeForVariant(NmtkThemeVariant variant) {
    final seed = _seedForVariant(variant);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: NmtkDesignTokens.backgroundLight,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: _buildTextTheme(ThemeData.light().textTheme),
      extensions: [
        NmtkThemeExtension(
          terminalBackground: const Color(0xFFE2E8F0),
          syntaxHighlightColor: seed,
          brandGradient: LinearGradient(
            colors: [colorScheme.primary, colorScheme.tertiary],
          ),
          glassmorphismColor: Colors.white.withValues(alpha: 0.7),
        ),
      ],
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: NmtkDesignTokens.cardShape,
        ),
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

  /// Returns a dark [ThemeData] tuned for the given [NmtkThemeVariant].
  ///
  /// For [NmtkThemeVariant.neurocnl] the scaffold background is set to the
  /// deep purple-black from [NmtkNeurocnlTokens.background] so the editor
  /// feels immersive.  All other variants fall back to the standard NMTK
  /// dark background.
  static ThemeData darkThemeForVariant(NmtkThemeVariant variant) {
    final seed = _seedForVariant(variant);

    // Per-variant dark surface overrides.
    final Color darkSurface = variant == NmtkThemeVariant.neurocnl
        ? NmtkNeurocnlTokens.background
        : NmtkDesignTokens.backgroundDark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      surface: darkSurface,
      onSurface: const Color(0xFFF1F5F9),
      surfaceContainerHighest: variant == NmtkThemeVariant.neurocnl
          ? NmtkNeurocnlTokens.surface
          : NmtkDesignTokens.surfaceDark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: darkSurface,
      textTheme: _buildTextTheme(ThemeData.dark().textTheme),
      extensions: [
        NmtkThemeExtension(
          terminalBackground: variant == NmtkThemeVariant.neurocnl
              ? NmtkNeurocnlTokens.surfaceVariant
              : const Color(0xFF0A0C16),
          syntaxHighlightColor: variant == NmtkThemeVariant.neurocnl
              ? NmtkNeurocnlTokens.synKeyword
              : const Color(0xFF60A5FA),
          brandGradient: LinearGradient(
            colors: [colorScheme.primary, colorScheme.secondaryContainer],
          ),
          glassmorphismColor: darkSurface.withValues(alpha: 0.8),
        ),
      ],
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: NmtkDesignTokens.cardShape,
          side: BorderSide(
            color: variant == NmtkThemeVariant.neurocnl
                ? NmtkNeurocnlTokens.border
                : const Color(0xFF1E293B),
            width: 1,
          ),
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
        backgroundColor: variant == NmtkThemeVariant.neurocnl
            ? NmtkNeurocnlTokens.surface
            : NmtkDesignTokens.surfaceDark,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // High Contrast Light Theme
  static ThemeData get highContrastLightTheme {
    final base = lightTheme;
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

  // High Contrast Dark Theme
  static ThemeData get highContrastDarkTheme {
    final base = darkTheme;
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
/// ADAPTIVE LAYOUT (MOBILE / TABLET / DESKTOP / WEB)
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
  // Native context-menu check (Optional: if we want to change behavior based on OS)
  bool get _isDesktopContext {
    if (kIsWeb) return true;
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double screenWidth = constraints.maxWidth;

        // Mobile Layout (< 600px)
        if (screenWidth < 600) {
          return Scaffold(
            body: widget.body,
            floatingActionButton: widget.floatingActionButton,
            bottomNavigationBar: NavigationBar(
              selectedIndex: widget.currentIndex,
              onDestinationSelected: widget.onNavigationTargetSelected,
              destinations: widget.destinations.map((d) {
                return NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon ?? d.icon),
                  label: d.label,
                );
              }).toList(),
            ),
          );
        }

        // Tablet/Desktop App-Rail Layout (600px - 1240px)
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

        // Full Desktop / Web Layout (>= 1240px)
        return Scaffold(
          floatingActionButton: widget.floatingActionButton,
          body: Row(
            children: [
              // Custom expressive drawer imitating the HTML specs provided
              Container(
                width: 256, // Modern drawer width
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
                        itemBuilder: (context, idx) {
                          final isSelected = widget.currentIndex == idx;
                          final dest = widget.destinations[idx];

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: NmtkDesignTokens.buttonShape,
                              child: InkWell(
                                borderRadius: NmtkDesignTokens.buttonShape,
                                // Defined Hover & Touch targets
                                hoverColor: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.08),
                                onTap: () =>
                                    widget.onNavigationTargetSelected(idx),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
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
                                    borderRadius: NmtkDesignTokens.buttonShape,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isSelected
                                            ? (dest.selectedIcon ?? dest.icon)
                                            : dest.icon,
                                        color: isSelected
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.onPrimaryContainer
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        dest.label,
                                        style: TextStyle(
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                          color: isSelected
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.onPrimaryContainer
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
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
    return Padding(
      padding: const EdgeInsets.all(24.0),
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
      ),
    );
  }
}

/// ----------------------------------------------------------------------------
/// DATACLASS FOR NAVIGATION ITEMS
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
