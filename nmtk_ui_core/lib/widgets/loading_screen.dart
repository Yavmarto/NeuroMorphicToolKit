import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/motion_tokens.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

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

// Inline semantic colors keep this widget self-contained inside ui_core.

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
    this.backgroundColor,
    this.foregroundColor,
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

  /// Background color of the loading screen.
  final Color? backgroundColor;

  /// Foreground color of the text.
  final Color? foregroundColor;

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
    _scaleAnimation =
        CurvedAnimation(
          parent: _scaleController,
          curve: NmtkMotionTokens.easeSpring,
        ).drive(
          Tween<double>(
            begin: NmtkMotionTokens.logoEntranceScaleBegin,
            end: 1.0,
          ),
        );
    _scaleController.forward();
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = widget.backgroundColor ?? scheme.surface;
    final fg = widget.foregroundColor ?? scheme.onSurface;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LogoBox(),
                      const SizedBox(height: 16),
                      Text(
                        widget.appName,
                        textAlign: TextAlign.center,
                        style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                          fontFamily: 'Space Grotesk',
                          fontSize: 18,
                          color: fg,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                _buildStateContent(widget.state, fg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStateContent(NmtkReadinessState state, Color fg) {
    switch (state) {
      case NmtkReadinessState.waiting:
        return _WaitingContent(
          message: widget.progressMessage ?? 'Starting up...',
          textColor: fg,
        );
      case NmtkReadinessState.ready:
        return const _ReadyContent();
      case NmtkReadinessState.degraded:
        return _DegradedContent(
          message:
              widget.degradedMessage ??
              'Some optional services are unavailable.',
          textColor: fg,
        );
      case NmtkReadinessState.failed:
        return _FailedContent(
          message: widget.errorMessage ?? 'A required service failed to start.',
          onRetry: widget.onRetry,
          textColor: fg,
        );
    }
  }
}

class _LogoBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = NmtkShellTokens.of(context);

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      alignment: Alignment.center,
      child: Text(
        'N',
        style: Zeta.of(context).textStyles.bodyMedium.copyWith(
          color: scheme.onPrimary,
          fontSize: 32,
          fontWeight: FontWeight.bold,
          height: 1,
        ),
      ),
    );
  }
}

class _WaitingContent extends StatelessWidget {
  const _WaitingContent({required this.message, required this.textColor});

  final String message;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(0.0, 200.0).toDouble();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: width,
              child: LinearProgressIndicator(
                backgroundColor: textColor.withValues(alpha: 0.15),
                color: Theme.of(context).colorScheme.primary,
                minHeight: 3,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              message,
              textAlign: TextAlign.center,
              style: Zeta.of(
                context,
              ).textStyles.bodyMedium.copyWith(fontSize: 14, color: textColor),
            ),
          ],
        );
      },
    );
  }
}

class _ReadyContent extends StatelessWidget {
  const _ReadyContent();

  @override
  Widget build(BuildContext context) {
    return Icon(
      ZetaIcons.check_circle_outline,
      color: NmtkShellTokens.of(context).healthyColor,
      size: 36,
    );
  }
}

class _DegradedContent extends StatelessWidget {
  const _DegradedContent({required this.message, required this.textColor});

  final String message;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(0.0, 280.0).toDouble();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ZetaIcons.warning_outline,
              color: NmtkShellTokens.of(context).warningColor,
              size: 36,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: width,
              child: SelectableText(
                message,
                textAlign: TextAlign.center,
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  fontSize: 13,
                  color: textColor,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FailedContent extends StatelessWidget {
  const _FailedContent({
    required this.message,
    this.onRetry,
    required this.textColor,
  });

  final String message;
  final VoidCallback? onRetry;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(0.0, 320.0).toDouble();
        final tokens = NmtkShellTokens.of(context);
        return Container(
          width: width,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: tokens.errorColor.withValues(alpha: 0.08),
            border: Border.all(
              color: tokens.errorColor.withValues(alpha: 0.35),
            ),
            borderRadius: BorderRadius.circular(tokens.radiusMd),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ZetaIcons.error_outline, color: tokens.errorColor, size: 36),
              const SizedBox(height: 12),
              SelectableText(
                message,
                textAlign: TextAlign.center,
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  fontSize: 14,
                  color: textColor,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                ZetaButton.negative(onPressed: onRetry, label: 'Retry'),
              ],
            ],
          ),
        );
      },
    );
  }
}
