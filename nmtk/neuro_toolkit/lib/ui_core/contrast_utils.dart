import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG 2.1 relative luminance helpers shared by the shell token and tone
/// palettes. Shared chrome must stay legible in both themes even when a
/// generated color scheme pairs a container with a mismatched foreground.

double _linearChannel(double channel) => channel <= 0.03928
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

/// WCAG 2.1 relative luminance of an opaque [color].
double nmtkRelativeLuminance(Color color) =>
    0.2126 * _linearChannel(color.r) +
    0.7152 * _linearChannel(color.g) +
    0.0722 * _linearChannel(color.b);

/// WCAG 2.1 contrast ratio between two opaque colors (1.0 to 21.0).
double nmtkContrastRatio(Color a, Color b) {
  final la = nmtkRelativeLuminance(a);
  final lb = nmtkRelativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Returns [foreground] when it already meets [floor] against [background].
/// Otherwise nudges it toward black (on a light background) or white (on a
/// dark background) until the floor is met, preserving as much of the
/// original hue as the contrast budget allows.
Color nmtkReadableForeground(
  Color foreground,
  Color background, {
  double floor = 4.5,
}) {
  if (nmtkContrastRatio(foreground, background) >= floor) return foreground;
  final blackRatio = nmtkContrastRatio(const Color(0xFF000000), background);
  final whiteRatio = nmtkContrastRatio(const Color(0xFFFFFFFF), background);
  final target = blackRatio >= whiteRatio
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);
  var adjusted = foreground;
  for (var step = 1; step <= 20; step++) {
    adjusted = Color.lerp(foreground, target, step / 20)!;
    if (nmtkContrastRatio(adjusted, background) >= floor) return adjusted;
  }
  return adjusted;
}
