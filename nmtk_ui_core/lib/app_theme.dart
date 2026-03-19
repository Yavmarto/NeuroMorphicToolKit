import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'widgets/nmtk_navigation_rail.dart';

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
/// APP THEME CONFIGURATION
/// ----------------------------------------------------------------------------

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
