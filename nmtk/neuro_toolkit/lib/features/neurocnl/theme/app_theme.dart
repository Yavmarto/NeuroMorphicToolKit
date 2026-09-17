import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' as ui_core;
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart'
    show NmtkNeurocnlTokens, NmtkThemeVariant, NmtkThemeExtension;
import 'package:neuro_toolkit/ui_core/shell_tokens.dart' show NmtkShellTokens;

export 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart'
    show NmtkThemeVariant, NmtkThemeExtension, NmtkNeurocnlTokens;

/// Neuromorphic-inspired theme for neurocnl Studio.
///
/// Color constants are forwarded from [NmtkNeurocnlTokens] in the root
/// nmtk_ui_core package. ThemeData is built by the centralized [ui_core.AppTheme]
/// using [NmtkThemeVariant.neurocnl], ensuring a consistent suite-wide look
/// while preserving the purple/lavender identity of this module.
class AppTheme {
  AppTheme._();

  // ── Brand colours (forwarded for backward compatibility) ───────
  static const Color background = NmtkNeurocnlTokens.background;
  static const Color surface = NmtkNeurocnlTokens.surface;
  static const Color surfaceVariant = NmtkNeurocnlTokens.surfaceVariant;
  static const Color primary = NmtkNeurocnlTokens.primary;
  static const Color primaryDim = NmtkNeurocnlTokens.primaryDim;
  static const Color success = NmtkNeurocnlTokens.success;
  static const Color error = NmtkNeurocnlTokens.error;
  static const Color warning = NmtkNeurocnlTokens.warning;
  static const Color info = NmtkNeurocnlTokens.info;
  static const Color textPrimary = NmtkNeurocnlTokens.textPrimary;
  static const Color textSecondary = NmtkNeurocnlTokens.textSecondary;
  static const Color border = NmtkNeurocnlTokens.border;

  // ── Syntax highlighting colours (forwarded) ────────────────────
  static const Color synKeyword = NmtkNeurocnlTokens.synKeyword;
  static const Color synSubject = NmtkNeurocnlTokens.synSubject;
  static const Color synNumber = NmtkNeurocnlTokens.synNumber;
  static const Color synComment = NmtkNeurocnlTokens.synComment;
  static const Color synString = NmtkNeurocnlTokens.synString;
  static const Color synVerb = NmtkNeurocnlTokens.synVerb;
  static const Color synUnit = NmtkNeurocnlTokens.synUnit;

  // ── Node / Edge colours (forwarded) ───────────────────────────
  static const Color nodeEnsemble = NmtkNeurocnlTokens.nodeEnsemble;
  static const Color nodeMotor = NmtkNeurocnlTokens.nodeMotor;
  static const Color nodeInterneuron = NmtkNeurocnlTokens.nodeInterneuron;
  static const Color nodeGenericEnsemble =
      NmtkNeurocnlTokens.nodeGenericEnsemble;
  static const Color nodeInput = NmtkNeurocnlTokens.nodeInput;
  static const Color nodeErrorInput = NmtkNeurocnlTokens.nodeErrorInput;
  static const Color edgeExcitatory = NmtkNeurocnlTokens.edgeExcitatory;
  static const Color edgeInhibitory = NmtkNeurocnlTokens.edgeInhibitory;
  static const Color edgePlastic = NmtkNeurocnlTokens.edgePlastic;

  // ── ThemeData ──────────────────────────────────────────────────
  static const String uiFontFamily = ui_core.NmtkFontFamilies.ui;
  static const String monospaceFontFamily = ui_core.NmtkFontFamilies.monospace;
  static const String fontPackage = ui_core.NmtkFontFamilies.package;

  static Color healthyColorOf(BuildContext context) =>
      ui_core.NmtkShellTokens.of(context).healthyColor;

  static Color errorColorOf(BuildContext context) =>
      ui_core.NmtkShellTokens.of(context).errorColor;

  // ── Context-aware helpers (theme-adaptive) ─────────────────────
  static Color backgroundOf(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  static Color surfaceOf(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHighest;

  static Color textPrimaryOf(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color textSecondaryOf(BuildContext context) =>
      NmtkShellTokens.of(context).metadataForeground;

  static Color borderOf(BuildContext context) =>
      NmtkShellTokens.of(context).chromeBorder;

  static Color primaryOf(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  static Color errorOf(BuildContext context) =>
      Theme.of(context).colorScheme.error;

  static Color synKeywordOf(BuildContext context) =>
      Theme.of(context).extension<NmtkThemeExtension>()?.synKeyword ??
      NmtkNeurocnlTokens.synKeyword;

  static Color synNumberOf(BuildContext context) =>
      Theme.of(context).extension<NmtkThemeExtension>()?.synNumber ??
      NmtkNeurocnlTokens.synNumber;

  static Color synVerbOf(BuildContext context) =>
      Theme.of(context).extension<NmtkThemeExtension>()?.synString ??
      NmtkNeurocnlTokens.synVerb;

  static Color synUnitOf(BuildContext context) =>
      NmtkShellTokens.of(context).metadataForeground;

  static Color synCommentOf(BuildContext context) =>
      Theme.of(context).extension<NmtkThemeExtension>()?.synComment ??
      NmtkNeurocnlTokens.synComment;
}
