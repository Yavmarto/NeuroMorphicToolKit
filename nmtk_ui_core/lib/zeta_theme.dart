import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

export 'package:zeta_flutter/zeta_flutter.dart'
    show
        ZetaProvider,
        Zeta,
        ZetaColors,
        ZetaCustomTheme,
        ZetaContrast,
        ZetaPrimitives,
        ZetaButton,
        ZetaButtonType,
        ZetaTextInput,
        ZetaAvatar,
        ZetaAvatarSize,
        ZetaWidgetSize,
        ZetaWidgetBorder,
        ZetaStatusLabel,
        ZetaWidgetStatus,
        ZetaBadge,
        ZetaColorSwatch;

/// Central Zeta theme configuration for the NeuroMorphicToolKit suite.
///
/// Primary colour: Command Blue `#1337EC`.
///
/// The NMTK custom theme (`id: 'nmtk'`) is passed to [ZetaProvider], which
/// generates the full Zeta semantic token set with Command Blue as
/// `mainPrimary`. Modules access Zeta semantics via `Zeta.of(context).colors`,
/// spacing via `Zeta.of(context).spacing`, and radius via
/// `Zeta.of(context).radius`.
///
/// ## Usage
///
/// ```dart
/// NmtkZetaTheme.wrap(
///   builder: (context, light, dark, mode) => MaterialApp(
///     themeMode: mode,
///     theme: light,
///     darkTheme: dark,
///     home: const MyWidget(),
///   ),
/// )
/// ```
class NmtkZetaTheme {
  NmtkZetaTheme._();

  /// Zeta custom theme identifier used by [ZetaProvider].
  static const String id = 'nmtk';

  /// NMTK primary — Command Blue.
  ///
  /// Replaces Zeta's default blue primary (`#0073e6` light / `#599fe5` dark).
  /// This color is authoritative; all references to the brand primary in
  /// design.json, DESIGN.md, and NmtkDesignTokens use this value.
  static const Color primary = Color(0xFF1337EC);

  /// Returns the [ZetaCustomTheme] pre-configured for NMTK.
  static ZetaCustomTheme get customTheme => ZetaCustomTheme(
        id: id,
        primary: primary,
      );

  /// Wraps [builder] in a [ZetaProvider] pre-configured with the NMTK theme.
  ///
  /// Pass [initialThemeMode] to override the default (dark).
  static Widget wrap({
    required Widget Function(
      BuildContext context,
      ThemeData light,
      ThemeData dark,
      ThemeMode mode,
    ) builder,
    ThemeMode initialThemeMode = ThemeMode.dark,
  }) {
    return ZetaProvider(
      initialTheme: id,
      initialThemeMode: initialThemeMode,
      customThemes: [customTheme],
      builder: builder,
    );
  }
}
