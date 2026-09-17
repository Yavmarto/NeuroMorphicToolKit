import 'package:flutter/material.dart';

/// Semantic colors and shapes mirroring the launcher's `NmtkShellTokens`.
///
/// The Connect screen is part of the standalone `neurohub_frontend` package,
/// which cannot import `neuro_toolkit` without creating a dependency cycle
/// (the app imports this package via `path:`). To keep the screen visually
/// consistent with the rest of the suite, the canonical values from
/// `nmtk/neuro_toolkit/lib/ui_core/shell_tokens.dart` are copied here and must
/// stay in sync with that file.
abstract final class GithubConnectTokens {
  static const Color error = Color(0xFFEF4444);
  static const Color success = Color(0xFF22C55E);
  static const Color info = Color(0xFF38BDF8);

  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double sectionGap = 16;
}
