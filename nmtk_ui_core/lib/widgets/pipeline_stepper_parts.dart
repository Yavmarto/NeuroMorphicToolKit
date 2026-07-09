part of 'pipeline_stepper.dart';

class _PipelineStep extends StatefulWidget {
  final NmtkPipelineStepData data;
  final bool selected;
  final VoidCallback? onTap;
  final Color accentColor;

  const _PipelineStep({
    super.key,
    required this.data,
    this.selected = false,
    this.onTap,
    required this.accentColor,
  });

  @override
  State<_PipelineStep> createState() => _PipelineStepState();
}

class _PipelineStepState extends State<_PipelineStep>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.06,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.06,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 60,
      ),
    ]).animate(_pulseCtrl);
  }

  @override
  void didUpdateWidget(covariant _PipelineStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fire a pulse whenever pulseTick increments on a running step, as long
    // as the user has not enabled reduced motion.
    final tickChanged = widget.data.pulseTick != oldWidget.data.pulseTick;
    final isRunning = widget.data.status == NmtkStepStatus.running;
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (tickChanged && isRunning && !reduced) {
      _pulseCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    final enabled =
        widget.data.status != NmtkStepStatus.idle || widget.onTap != null;

    Widget chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _getBgColor(context, theme, tokens),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(
          color: _getBorderColor(context, theme, tokens),
          width: widget.selected ? 1.6 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildIcon(context, theme, tokens),
          const SizedBox(width: 4),
          Text(
            widget.data.label,
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 11,
              fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    // Wrap in scale animation when running and pulseTick has ever been set.
    if (widget.data.status == NmtkStepStatus.running &&
        widget.data.pulseTick > 0) {
      chip = AnimatedBuilder(
        animation: _pulseScale,
        builder: (context, child) =>
            Transform.scale(scale: _pulseScale.value, child: child),
        child: chip,
      );
    }

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Semantics(
        button: widget.onTap != null,
        selected: widget.selected,
        label:
            '${widget.data.label} step, '
            'status: ${widget.data.status.name}'
            '${widget.data.detail != null ? ", ${widget.data.detail}" : ""}',
        child: widget.onTap == null
            ? chip
            : MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(onTap: widget.onTap, child: chip),
              ),
      ),
    );
  }

  Widget _buildIcon(
    BuildContext context,
    ThemeData theme,
    NmtkShellTokens tokens,
  ) {
    if (widget.data.status == NmtkStepStatus.running) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: widget.accentColor,
        ),
      );
    }

    IconData iconData;
    Color iconColor;

    switch (widget.data.status) {
      case NmtkStepStatus.idle:
        iconData = widget.data.icon ?? ZetaIcons.radio_button_unchecked;
        iconColor = widget.selected
            ? widget.accentColor
            : theme.colorScheme.onSurfaceVariant;
      case NmtkStepStatus.success:
        iconData = ZetaIcons.check_circle;
        iconColor = tokens.healthyColor;
      case NmtkStepStatus.error:
        iconData = ZetaIcons.error;
        iconColor = tokens.errorColor;
      default:
        iconData = widget.data.icon ?? ZetaIcons.radio_button_unchecked;
        iconColor = theme.colorScheme.onSurfaceVariant;
    }

    return Icon(iconData, size: 14, color: iconColor);
  }

  Color _getBgColor(
    BuildContext context,
    ThemeData theme,
    NmtkShellTokens tokens,
  ) {
    final base = switch (widget.data.status) {
      NmtkStepStatus.idle => theme.colorScheme.surface,
      NmtkStepStatus.running => widget.accentColor.withValues(alpha: 0.12),
      NmtkStepStatus.success => tokens.healthyColor.withValues(alpha: 0.1),
      NmtkStepStatus.error => tokens.errorColor.withValues(alpha: 0.1),
    };
    return widget.selected
        ? Color.alphaBlend(widget.accentColor.withValues(alpha: 0.06), base)
        : base;
  }

  Color _getBorderColor(
    BuildContext context,
    ThemeData theme,
    NmtkShellTokens tokens,
  ) {
    if (widget.selected) {
      return widget.accentColor;
    }
    switch (widget.data.status) {
      case NmtkStepStatus.idle:
        return theme.colorScheme.outlineVariant;
      case NmtkStepStatus.running:
        return widget.accentColor;
      case NmtkStepStatus.success:
        return tokens.healthyColor.withValues(alpha: 0.3);
      case NmtkStepStatus.error:
        return tokens.errorColor.withValues(alpha: 0.3);
    }
  }
}

class _StepConnector extends StatelessWidget {
  final bool active;

  const _StepConnector({super.key, required this.active});

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final theme = Theme.of(context);
    // ponytail: fixed 30px slot (22 + 4px margin each side) matches _ConnectorSlotButton
    // so AnimatedSwitcher cross-fades with zero width delta — no spatial pop.
    return Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      child: Icon(
        ZetaIcons.arrow_forward,
        size: 10,
        color: active
            ? tokens.healthyColor
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
      ),
    );
  }
}

// ── _ConnectorSlotButton ──────────────────────────────────────────────────────
// ponytail: tiny inline +/− button with hover/press animation in connector slots.

class _ConnectorSlotButton extends StatefulWidget {
  const _ConnectorSlotButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_ConnectorSlotButton> createState() => _ConnectorSlotButtonState();
}

class _ConnectorSlotButtonState extends State<_ConnectorSlotButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    final scale = _pressed ? 0.88 : (_hovered ? 1.12 : 1.0);
    final bgColor = _hovered
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surface;
    final borderColor = _hovered
        ? theme.colorScheme.outlineVariant
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.6);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              width: 22,
              height: 22,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: bgColor,
                // Radius 11 on a fixed 22px box renders identically once
                // Flutter clamps to half the box side — using the sanctioned
                // radiusSm token here is a no-op visually, not a regression.
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(
                  color: borderColor,
                  width: _hovered ? 1.5 : 1,
                ),
              ),
              child: Icon(
                widget.icon,
                size: 13,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
