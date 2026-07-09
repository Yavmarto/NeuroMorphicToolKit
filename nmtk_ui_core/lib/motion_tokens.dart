import 'package:flutter/material.dart';

/// NeuroMorphicToolKit motion token system.
///
/// All animation durations and easing curves across the suite must be drawn
/// from this class. Do not use ad-hoc `Duration(milliseconds: X)` literals
/// in animation widgets — reference the nearest token here instead.
///
/// ## Duration scale
///
/// | Token           | Ms  | Use when                                  |
/// |-----------------|-----|-------------------------------------------|
/// | [durationFast]  | 120 | Hover states, tooltips, micro-interactions|
/// | [durationBase]  | 220 | Standard transitions (expand/collapse)    |
/// | [durationSlow]  | 350 | Page/route transitions, loading sequences |
/// | [durationSpring]| 180 | Spring-back after tap, badge pop          |
///
/// ## Easing curves
///
/// | Token          | Curve              | Use when                     |
/// |----------------|--------------------|------------------------------|
/// | [easeEnter]    | Curves.easeOut     | Elements entering the screen |
/// | [easeExit]     | Curves.easeIn      | Elements leaving the screen  |
/// | [easeStandard] | Curves.easeInOut   | In-place transitions         |
/// | [easeSpring]   | Curves.easeOutQuart| Pop / spring-back moments    |
///
/// ## Usage
///
/// ```dart
/// AnimatedContainer(
///   duration: NmtkMotionTokens.durationBase,
///   curve: NmtkMotionTokens.easeStandard,
///   ...
/// )
/// ```
class NmtkMotionTokens {
  NmtkMotionTokens._();

  // ── Duration scale ──────────────────────────────────────────────────────────

  /// 120 ms — hover states, tooltip appearance, micro-interaction feedback.
  static const Duration durationFast = Duration(milliseconds: 120);

  /// 220 ms — standard expand/collapse, chip open, card lift.
  static const Duration durationBase = Duration(milliseconds: 220);

  /// 350 ms — page/route transitions, loading-screen entrance/exit.
  static const Duration durationSlow = Duration(milliseconds: 350);

  /// 180 ms — spring-back on tap-up, back-button appearance.
  static const Duration durationSpring = Duration(milliseconds: 180);

  // ── Easing curves ───────────────────────────────────────────────────────────

  /// `Curves.easeOut` — elements entering the viewport.
  static const Curve easeEnter = Curves.easeOut;

  /// `Curves.easeIn` — elements leaving the viewport.
  static const Curve easeExit = Curves.easeIn;

  /// `Curves.easeInOut` — in-place transforms (expand, slide, reorder).
  static const Curve easeStandard = Curves.easeInOut;

  /// `Curves.easeOutQuart` — spring-back / pop moments (tap-up, badge appear).
  static const Curve easeSpring = Curves.easeOutQuart;

  // ── Shared-axis slide offsets ───────────────────────────────────────────────

  /// Standard horizontal slide distance for forward navigation.
  static const Offset slideForwardBegin = Offset(0.06, 0.0);

  /// Standard horizontal slide distance for backward navigation.
  static const Offset slideBackwardBegin = Offset(-0.06, 0.0);

  /// Standard vertical slide distance for drill-in navigation.
  static const Offset slideDrillBegin = Offset(0.0, 0.04);

  // ── Scale constants ─────────────────────────────────────────────────────────

  /// Scale-down factor on button tap-down (pressed state).
  static const double tapDownScale = 0.96;

  /// Starting scale for logo entrance animation.
  static const double logoEntranceScaleBegin = 0.80;

  /// Starting scale for back-button spring-in.
  static const double backButtonScaleBegin = 0.70;
}
