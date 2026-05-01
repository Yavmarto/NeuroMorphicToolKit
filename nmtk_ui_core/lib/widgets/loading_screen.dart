import 'dart:async';

import 'package:flutter/material.dart';

import '../motion_tokens.dart';

/// Readiness state for the [NmtkLoadingScreen].
enum NmtkReadinessState {
  /// Backend health polling is in progress.
  waiting,

  /// All required modules are healthy.
  ready,

  /// One or more optional modules failed; user can proceed with a warning.
  degraded,

  /// One or more required modules timed out; show error and offer retry.
  failed,
}

// ── Inline color constants (no nmtk_ui_core imports allowed here) ──────────
const Color _kBackground = Color(0xFF101322);
const Color _kLogoBg = Color(0xFF1337EC);
const Color _kTextLight = Color(0xFFCBD5E1);
const Color _kGreen = Color(0xFF22C55E);
const Color _kYellow = Color(0xFFF59E0B);
const Color _kRed = Color(0xFFEF4444);

/// Full-screen loading/readiness screen shown while backend modules start up.
///
/// This widget is purely callback-based with no Provider or Riverpod dependency.
class NmtkLoadingScreen extends StatefulWidget {
  const NmtkLoadingScreen({
    super.key,
    required this.state,
    this.progressMessage,
    this.errorMessage,
    this.degradedMessage,
    this.onRetry,
    this.appName = 'NeuroMorphicToolKit',
  });

  /// Current readiness state.
  final NmtkReadinessState state;

  /// Optional message shown in [NmtkReadinessState.waiting] state.
  final String? progressMessage;

  /// Optional message shown in [NmtkReadinessState.failed] state.
  final String? errorMessage;

  /// Optional message shown in [NmtkReadinessState.degraded] state.
  final String? degradedMessage;

  /// Called when the Retry button is tapped in [NmtkReadinessState.failed] state.
  final VoidCallback? onRetry;

  /// Application name displayed below the logo.
  final String appName;

  @override
  State<NmtkLoadingScreen> createState() => _NmtkLoadingScreenState();
}

class _NmtkLoadingScreenState extends State<NmtkLoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: NmtkMotionTokens.durationSlow,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: NmtkMotionTokens.easeSpring,
    ).drive(Tween<double>(begin: NmtkMotionTokens.logoEntranceScaleBegin, end: 1.0));
    _scaleController.forward();
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Logo + app name block (animated entrance) ──
            ScaleTransition(
              scale: _scaleAnimation,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LogoBox(),
                  const SizedBox(height: 16),
                  Text(
                    widget.appName,
                    style: const TextStyle(
                      fontFamily: 'Space Grotesk',
                      fontSize: 18,
                      color: _kTextLight,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // ── State-specific content ──
            _buildStateContent(widget.state),
          ],
        ),
      ),
    );
  }

  Widget _buildStateContent(NmtkReadinessState state) {
    switch (state) {
      case NmtkReadinessState.waiting:
        return _WaitingContent(
          message: widget.progressMessage ?? 'Starting up…',
        );
      case NmtkReadinessState.ready:
        return const _ReadyContent();
      case NmtkReadinessState.degraded:
        return _DegradedContent(
          message: widget.degradedMessage ??
              'Some optional services are unavailable.',
        );
      case NmtkReadinessState.failed:
        return _FailedContent(
          message: widget.errorMessage ??
              'A required service failed to start.',
          onRetry: widget.onRetry,
        );
    }
  }
}

// ── Logo ──────────────────────────────────────────────────────────────────

class _LogoBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: _kLogoBg,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: const Text(
        'N',
        style: TextStyle(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.bold,
          height: 1,
        ),
      ),
    );
  }
}

// ── Waiting ───────────────────────────────────────────────────────────────

class _WaitingContent extends StatelessWidget {
  const _WaitingContent({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 200,
          child: LinearProgressIndicator(
            backgroundColor: _kTextLight.withValues(alpha: 0.15),
            color: _kLogoBg,
            minHeight: 3,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          message,
          style: const TextStyle(
            fontSize: 14,
            color: _kTextLight,
          ),
        ),
      ],
    );
  }
}

// ── Ready ─────────────────────────────────────────────────────────────────

class _ReadyContent extends StatelessWidget {
  const _ReadyContent();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.check_circle_outline,
      color: _kGreen,
      size: 36,
    );
  }
}

// ── Degraded ──────────────────────────────────────────────────────────────

class _DegradedContent extends StatelessWidget {
  const _DegradedContent({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          color: _kYellow,
          size: 36,
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 280,
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: _kTextLight,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Failed ────────────────────────────────────────────────────────────────

class _FailedContent extends StatelessWidget {
  const _FailedContent({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kRed.withValues(alpha: 0.08),
        border: Border.all(color: _kRed.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            color: _kRed,
            size: 36,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: _kTextLight,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: _kRed,
                side: const BorderSide(color: _kRed),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}
