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

// ─────────────────────────────────────────────────────────────────────────────
// Shared-axis page transition builder
// ─────────────────────────────────────────────────────────────────────────────

/// Returns a [PageTransitionsBuilder] that applies a shared-axis horizontal
/// slide transition using [NmtkMotionTokens.durationSlow] and
/// [NmtkMotionTokens.easeStandard].
///
/// Use this in [ThemeData.pageTransitionsTheme] to enable suite-wide
/// transitions:
///
/// ```dart
/// ThemeData(
///   pageTransitionsTheme: PageTransitionsTheme(
///     builders: {
///       TargetPlatform.macOS: NmtkSharedAxisTransitionBuilder(),
///       TargetPlatform.linux: NmtkSharedAxisTransitionBuilder(),
///       TargetPlatform.windows: NmtkSharedAxisTransitionBuilder(),
///     },
///   ),
/// )
/// ```
class NmtkSharedAxisTransitionBuilder extends PageTransitionsBuilder {
  const NmtkSharedAxisTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _NmtkSharedAxisTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

class _NmtkSharedAxisTransition extends StatelessWidget {
  const _NmtkSharedAxisTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final enterSlide = Tween<Offset>(
      begin: NmtkMotionTokens.slideForwardBegin,
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: animation,
        curve: NmtkMotionTokens.easeEnter,
      ),
    );
    final exitSlide = Tween<Offset>(
      begin: Offset.zero,
      end: NmtkMotionTokens.slideBackwardBegin,
    ).animate(
      CurvedAnimation(
        parent: secondaryAnimation,
        curve: NmtkMotionTokens.easeExit,
      ),
    );
    return SlideTransition(
      position: exitSlide,
      child: SlideTransition(
        position: enterSlide,
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.6, curve: NmtkMotionTokens.easeEnter),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tap-scale button wrapper
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps any widget in a tap-responsive scale animation.
///
/// Scales down to [NmtkMotionTokens.tapDownScale] on press and springs back
/// using [NmtkMotionTokens.easeSpring] on release.
class NmtkTapScaleWrapper extends StatefulWidget {
  const NmtkTapScaleWrapper({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  State<NmtkTapScaleWrapper> createState() => _NmtkTapScaleWrapperState();
}

class _NmtkTapScaleWrapperState extends State<NmtkTapScaleWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: NmtkMotionTokens.durationFast,
      reverseDuration: NmtkMotionTokens.durationSpring,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: NmtkMotionTokens.tapDownScale,
    ).animate(
      CurvedAnimation(parent: _controller, curve: NmtkMotionTokens.easeEnter),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.enabled) _controller.forward();
  }

  void _onTapUp(TapUpDetails _) {
    if (widget.enabled) _controller.reverse();
  }

  void _onTapCancel() {
    if (widget.enabled) _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(scale: _scaleAnimation, child: widget.child),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pulsing status dot
// ─────────────────────────────────────────────────────────────────────────────

/// A small status dot that pulses when [isPulsing] is true (degraded/failed).
///
/// Use for health indicator dots in status badges and header strips.
class NmtkStatusDot extends StatefulWidget {
  const NmtkStatusDot({
    super.key,
    required this.color,
    this.size = 8.0,
    this.isPulsing = false,
  });

  final Color color;
  final double size;

  /// When true the dot oscillates between 0.5× and 1.2× scale to draw
  /// attention to a degraded or failed state.
  final bool isPulsing;

  @override
  State<NmtkStatusDot> createState() => _NmtkStatusDotState();
}

class _NmtkStatusDotState extends State<NmtkStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: NmtkMotionTokens.easeStandard),
    );
    if (widget.isPulsing) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(NmtkStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPulsing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isPulsing && _controller.isAnimating) {
      _controller
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (!widget.isPulsing) return dot;
    return ScaleTransition(scale: _pulseAnimation, child: dot);
  }
}
