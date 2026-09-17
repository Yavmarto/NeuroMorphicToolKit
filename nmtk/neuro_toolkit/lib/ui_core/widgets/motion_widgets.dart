import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neuro_toolkit/ui_core/motion_tokens.dart';

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
    final enterSlide =
        Tween<Offset>(
          begin: NmtkMotionTokens.slideForwardBegin,
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: NmtkMotionTokens.easeEnter),
        );
    final exitSlide =
        Tween<Offset>(
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
    _scaleAnimation =
        Tween<double>(begin: 1.0, end: NmtkMotionTokens.tapDownScale).animate(
          CurvedAnimation(
            parent: _controller,
            curve: NmtkMotionTokens.easeEnter,
          ),
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
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final canActivate = widget.enabled && widget.onTap != null;
    final child = disableAnimations
        ? widget.child
        : ScaleTransition(scale: _scaleAnimation, child: widget.child);

    return Semantics(
      button: widget.onTap != null,
      enabled: canActivate,
      child: FocusableActionDetector(
        enabled: canActivate,
        mouseCursor: canActivate
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (canActivate) {
                widget.onTap!();
              }
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: canActivate ? HitTestBehavior.opaque : null,
          onTap: canActivate ? widget.onTap : null,
          onTapDown: disableAnimations ? null : _onTapDown,
          onTapUp: disableAnimations ? null : _onTapUp,
          onTapCancel: disableAnimations ? null : _onTapCancel,
          child: child,
        ),
      ),
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
      CurvedAnimation(
        parent: _controller,
        curve: NmtkMotionTokens.easeStandard,
      ),
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
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    if (!widget.isPulsing || disableAnimations) return dot;
    return ScaleTransition(scale: _pulseAnimation, child: dot);
  }
}
