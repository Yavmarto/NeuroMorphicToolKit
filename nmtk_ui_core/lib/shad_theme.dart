// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

// ─── Re-exports consumed by module apps ─────────────────────────────────────
// Modules import nmtk_ui_core and get these types through the barrel so they
// do not need a direct shadcn_ui dependency for the theme layer. They still
// need `shadcn_ui` in their own pubspec to use ShadApp as the app root.
export 'package:shadcn_ui/shadcn_ui.dart'
    show ShadApp, ShadTheme, ShadThemeData, ShadColorScheme;

// ─────────────────────────────────────────────────────────────────────────────
/// Central Shadcn/UI theme for the NeuroMorphicToolKit suite.
///
/// ## Palette — "Indigo & Teal"
///
/// Every colour is expressed as a plain `Color(0xFFRRGGBB)` hex literal.
/// No `Colors.*` material-class references appear in this file.  The
/// palette is self-contained and legible without cross-referencing the
/// Flutter material colour table.
///
/// ### Design intent
///
/// | Role          | Light               | Dark                |
/// |---------------|---------------------|---------------------|
/// | Primary       | Indigo-600 #4F46E5  | Indigo-400 #818CF8  |
/// | Accent        | Teal-500   #14B8A6  | Teal-400   #2DD4BF  |
/// | Background    | Near-white #FAFAFB  | CNL surface #0F0D1A |
/// | Border tint   | Violet-200 #DDD6FE  | CNL border #3D3560  |
///
/// *Primary* — deep indigo.  Technical confidence without generic blue.
/// *Accent*  — warm teal.  Playful complement; used for hovers, selections,
/// and interactive affordances across the Shadcn component layer.
///
/// The dark palette mirrors the established `NmtkNeurocnlTokens` surface
/// colours so the Shadcn layer integrates seamlessly with the rest of the
/// suite without introducing a second dark palette.
///
/// ## Border-radius
///
/// Default shadcn radius is 8 px (matches the web shadcn defaults).
/// We override to **12 px** (matching `NmtkDesignTokens.buttonShape`) for
/// a softer, "playfessional" feel — rounded without feeling like a mobile
/// bubble-UI.
///
/// ## Usage
///
/// ### Wrapping a module app
///
/// ```dart
/// // In each module's main.dart — switch MaterialApp → ShadApp.material
/// ShadApp.material(
///   themeMode: ThemeMode.dark,
///   theme: NmtkShadTheme.light,
///   darkTheme: NmtkShadTheme.dark,
///   // Retain the existing Material 3 theme so non-Shadcn widgets stay styled.
///   materialThemeBuilder: (context, shadTheme) =>
///       AppTheme.darkThemeForVariant(NmtkThemeVariant.neurocnl),
///   home: const MyHomeWidget(),
/// )
/// ```
///
/// ### Using Shadcn components in a widget tree
///
/// If the root is already a `ShadApp`, Shadcn components resolve the theme
/// automatically.  In tests or narrow widget subtrees you can inject the
/// theme manually:
///
/// ```dart
/// ShadTheme(
///   data: NmtkShadTheme.light,
///   child: ShadButton(child: const Text('Action')),
/// )
/// ```
// ─────────────────────────────────────────────────────────────────────────────

class NmtkShadTheme {
  NmtkShadTheme._();

  // ── Shared radius ─────────────────────────────────────────────────────────
  //
  // 12 px — one step softer than the shadcn default (8 px), aligned with
  // NmtkDesignTokens.buttonShape (BorderRadius.circular(16)) at the midpoint.
  // Applied to BOTH the ShadThemeData wrapper AND the ShadColorScheme token so
  // all component layers receive the same value regardless of which surface
  // a component reads from.
  static const BorderRadius _kRadius = BorderRadius.all(Radius.circular(12));

  // ────────────────────────────────────────────────────────────────────────
  // LIGHT COLOUR SCHEME
  // Indigo primary + teal accent on a clean near-white background.
  // Borders and surfaces carry a faint violet tint so the chrome breathes
  // the same hue without being heavy.
  // ────────────────────────────────────────────────────────────────────────

  static ShadColorScheme get _lightScheme => const ShadColorScheme(
    // ── Surfaces ─────────────────────────────────────────────────────
    /// Scaffold / page background — near-white with an imperceptible
    /// warm cast; avoids the clinical flatness of pure #FFFFFF.
    background: Color(0xFFF8FAFC),
    foreground: Color(0xFF0F172A),

    // Card surfaces are pure white so they lift clearly off the
    // slightly-tinted background, creating visual hierarchy without
    // using drop shadows.
    card: Color(0xFFFFFFFF),
    cardForeground: Color(0xFF0F172A),

    // Popovers, dropdowns, command-palette — also pure white so they
    // feel elevated above card surfaces.
    popover: Color(0xFFFFFFFF),
    popoverForeground: Color(0xFF18181B),

    // ── Primary — deep indigo ─────────────────────────────────────
    /// Primary brand colour.  Indigo-600 sits at the confident,
    /// "technical authority" end of the spectrum while still reading
    /// as vibrant and modern.
    primary: Color(0xFF0EA5E9),
    primaryForeground: Color(0xFFF8FAFC),

    // ── Secondary — light indigo tint ────────────────────────────
    /// Tinted surface for secondary buttons, selected-row backgrounds,
    /// and subtle highlights.  Indigo-50 is barely-perceptible in
    /// isolation but communicates grouping at a glance.
    secondary: Color(0xFFF1F5F9),
    secondaryForeground: Color(0xFF0F172A),

    // ── Muted — lavender-gray neutral ────────────────────────────
    /// Low-priority surface: disabled states, placeholder backgrounds,
    /// skeleton loaders.  Slightly lavender to stay in family.
    muted: Color(0xFFF8FAFC),
    mutedForeground: Color(0xFF64748B),

    // ── Accent — teal ────────────────────────────────────────────
    /// The "playful" pole of the palette.  Teal-500 complements indigo
    /// by sitting on the opposite warm-cool arc without clashing.
    /// Used for: hover highlights on menu items, keyboard-focused rings
    /// in non-primary contexts, selected-chip fills, and interactive
    /// affordances in Shadcn components.
    accent: Color(0xFF94A3B8),
    accentForeground: Color(0xFFFFFFFF),

    // ── Destructive ───────────────────────────────────────────────
    /// Destructive actions — red-600.  Aligned with NmtkShellTokens
    /// errorColor territory (red-500) without being identical.
    destructive: Color(0xFFDC2626),
    destructiveForeground: Color(0xFFFEF2F2),

    // ── Chrome ────────────────────────────────────────────────────
    /// Card / input borders — violet-200.  Soft enough to recede but
    /// tinted so the chrome feels intentional rather than generic grey.
    border: Color(0xFFE2E8F0),
    input: Color(0xFFF1F5F9),
    ring: Color(0xFF0EA5E9),
    selection: Color(0xFFE0F2FE),
  );

  // ────────────────────────────────────────────────────────────────────────
  // DARK COLOUR SCHEME
  // Surfaces deliberately match NmtkNeurocnlTokens so the Shadcn component
  // layer integrates with the neurocnl studio and the broader suite dark
  // theme without introducing a second dark palette.  Primary lifts to a
  // brighter indigo-400 so it remains legible on dark surfaces.
  // ────────────────────────────────────────────────────────────────────────

  static ShadColorScheme get _darkScheme => const ShadColorScheme(
    // ── Surfaces — neurocnl-aligned ───────────────────────────────
    /// Deep violet-black — matches NmtkNeurocnlTokens.background
    /// (#0F0D1A) so Shadcn pages blend with the existing dark layout.
    background: Color(0xFF08090A),
    foreground: Color(0xFFF1F5F9),

    // Card surfaces — one level above the background.
    // Matches NmtkNeurocnlTokens.surface (#1A1625).
    card: Color(0xFF0F172A),
    cardForeground: Color(0xFFF1F5F9),

    // Popover / dropdown — one level above cards.
    // Matches NmtkNeurocnlTokens.surfaceVariant (#231E35).
    popover: Color(0xFF242426),
    popoverForeground: Color(0xFFE5E7EB),

    // ── Primary — lifted indigo ───────────────────────────────────
    /// Indigo-400 — brighter than the light-mode indigo-600 so it
    /// achieves the same visual weight on dark backgrounds without
    /// washing out.
    primary: Color(0xFF38BDF8),
    primaryForeground: Color(0xFF08090A),

    // ── Secondary ─────────────────────────────────────────────────
    secondary: Color(0xFF1E293B),
    secondaryForeground: Color(0xFF94A3B8),
    muted: Color(0xFF0F172A),
    mutedForeground: Color(0xFF475569),

    // ── Accent — brighter teal ────────────────────────────────────
    /// Teal-400 — one step lighter than light-mode teal-500 to
    /// compensate for the dark background and maintain visual vibrancy.
    accent: Color(0xFF475569),
    accentForeground: Color(0xFFF1F5F9),

    // ── Destructive ───────────────────────────────────────────────
    /// Red-500 — matches NmtkShellTokens.errorColor exactly so Shadcn
    /// destructive states read the same as suite-level error badges.
    destructive: Color(0xFFEF4444),
    destructiveForeground: Color(0xFFFEF2F2),

    // ── Chrome ────────────────────────────────────────────────────
    /// Matches NmtkNeurocnlTokens.border (#3D3560) — the same violet-
    /// tinted separator used throughout the CNL studio.
    border: Color(0xFF1E293B),
    input: Color(0xFF0F172A),
    ring: Color(0xFF38BDF8),
    selection: Color(0xFF0C4A6E),
  );

  // ── Public API ────────────────────────────────────────────────────────────

  /// Light [ShadThemeData] for the suite.
  ///
  /// Pass to [ShadApp.theme] (or [ShadApp.material]'s `theme` parameter).
  /// The `radius` is set to 12 px — softer than the shadcn default (8 px)
  /// and aligned with [NmtkDesignTokens.buttonShape].
  static ShadThemeData get light => ShadThemeData(
    brightness: Brightness.light,
    colorScheme: _lightScheme,
    radius: _kRadius,
  );

  /// Dark [ShadThemeData] for the suite.
  ///
  /// Pass to [ShadApp.darkTheme] (or [ShadApp.material]'s `darkTheme`).
  static ShadThemeData get dark => ShadThemeData(
    brightness: Brightness.dark,
    colorScheme: _darkScheme,
    radius: _kRadius,
  );

  // ── Convenience accessor ──────────────────────────────────────────────────

  /// Resolves the correct [ShadThemeData] from the ambient [ShadTheme].
  ///
  /// Equivalent to `ShadTheme.of(context)` — provided here so widgets
  /// can import a single symbol from `nmtk_ui_core` instead of mixing
  /// `nmtk_ui_core` and `shadcn_ui` imports.
  static ShadThemeData of(BuildContext context) => ShadTheme.of(context);
}
