import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

// ── Platform color palette ────────────────────────────────────────────────

/// Assigns a deterministic color to each platform by its index in the summary
/// list.  Uses Zeta semantic colors so it stays correct in light/dark mode.
Color platformColor(int index, ZetaColors colors) {
  const cycle = 6;
  switch (index % cycle) {
    case 0:
      return colors.mainPrimary;
    case 1:
      return colors.mainSecondary;
    case 2:
      return colors.mainPositive;
    case 3:
      return colors.mainWarning;
    case 4:
      return colors.mainNegative;
    case 5:
    default:
      return colors.mainInfo;
  }
}

// ── Comparison view root ──────────────────────────────────────────────────

/// Full-screen compare mode overlay rendered over the canvas background.
///
/// Shows:
/// - Multi-line loss curve chart (one line per platform)
/// - Multi-line accuracy curve chart (if any platform reported accuracy)
/// - Summary metrics table in the right sidebar
/// - Same bottom action bar as the per-platform view

// ── Comparison sidebar (metrics + optional activity heatmap tabs) ─────────

// ── Activity similarity heatmap ───────────────────────────────────────────

// ── Multi-platform line chart ─────────────────────────────────────────────

enum CurveChartType { loss, accuracy }
