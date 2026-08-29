import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';

/// Execution control shared by the workflow's run surfaces.
class PlayStopButton extends StatefulWidget {
  const PlayStopButton({
    super.key,
    required this.enabled,
    required this.isRunning,
    required this.onPlay,
    required this.onStop,
    required this.l10n,
  });

  final bool enabled;
  final bool isRunning;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final AppLocalizations l10n;

  @override
  State<PlayStopButton> createState() => _PlayStopButtonState();
}

class _PlayStopButtonState extends State<PlayStopButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.isRunning) _pulseController.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(PlayStopButton old) {
    super.didUpdateWidget(old);
    if (widget.isRunning && !old.isRunning) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isRunning && old.isRunning) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final healthyColor = AppTheme.healthyColorOf(context);

    if (widget.isRunning) {
      // Running state: animated stop button.
      return Tooltip(
        message: widget.l10n.stopSimulation,
        child: InkWell(
          onTap: widget.onStop,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, _) => Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    value: null,
                    color: healthyColor.withValues(alpha: _pulseAnim.value),
                  ),
                ),
                Icon(
                  ZetaIcons.stop,
                  key: const Key('stop-icon'),
                  size: 18,
                  color: healthyColor,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Idle state: play button.
    final color = widget.enabled ? healthyColor : AppTheme.textSecondary;
    return Tooltip(
      message: widget.enabled
          ? widget.l10n.runSimulation
          : widget.l10n.fixErrorsFirst,
      child: InkWell(
        onTap: widget.enabled ? widget.onPlay : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.enabled
                ? healthyColor.withValues(alpha: 0.12)
                : Colors.transparent,
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          alignment: Alignment.center,
          child: Icon(
            ZetaIcons.play,
            key: const Key('play-icon'),
            size: 20,
            color: color,
          ),
        ),
      ),
    );
  }
}
