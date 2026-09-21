import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';

class _ValidationOverlaySummary {
  const _ValidationOverlaySummary({
    required this.parseErrors,
    required this.layer1Failures,
    required this.layer2Failures,
    required this.validationResult,
    required this.isRunning,
  });

  factory _ValidationOverlaySummary.fromPipeline(PipelineState pipeline) {
    return _ValidationOverlaySummary(
      parseErrors: pipeline.parseResult?.errors ?? 0,
      layer1Failures: pipeline.validateResult?.layer1.failed.length ?? 0,
      layer2Failures: pipeline.validateResult?.layer2.checksFailed.length ?? 0,
      validationResult: pipeline.validateResult,
      isRunning:
          pipeline.parseStatus == StepStatus.running ||
          pipeline.validateStatus == StepStatus.running,
    );
  }

  final int parseErrors;
  final int layer1Failures;
  final int layer2Failures;
  final ValidationResult? validationResult;
  final bool isRunning;

  @override
  bool operator ==(Object other) {
    return other is _ValidationOverlaySummary &&
        other.parseErrors == parseErrors &&
        other.layer1Failures == layer1Failures &&
        other.layer2Failures == layer2Failures &&
        other.validationResult == validationResult &&
        other.isRunning == isRunning;
  }

  @override
  int get hashCode => Object.hash(
    parseErrors,
    layer1Failures,
    layer2Failures,
    validationResult,
    isRunning,
  );
}

final _validationOverlaySummaryProvider = Provider<_ValidationOverlaySummary>((
  ref,
) {
  return ref.watch(
    pipelineProvider.select(_ValidationOverlaySummary.fromPipeline),
  );
});

/// Public alias so part-files and other widgets can watch validation state
/// without depending on the private summary type.
final validationOverlaySummaryProvider = _validationOverlaySummaryProvider;

/// Inline validation chip for embedding in the CNL editor toolbar row.
///
/// Shows nothing when the spec is valid and results are available. Shows a
/// coloured chip with an error count when there are parse/validation failures.
/// Tapping the chip opens a floating popup anchored above-right of the chip
/// via [OverlayPortal] — it floats above all editor content and does not
/// disturb the toolbar row layout.
///
/// Unlike [ValidationOverlay] this widget is NOT [Positioned] — it can be
/// dropped directly into any [Row].
class CnlEditorValidationChip extends ConsumerStatefulWidget {
  const CnlEditorValidationChip({super.key});

  @override
  ConsumerState<CnlEditorValidationChip> createState() =>
      _CnlEditorValidationChipState();
}

class _CnlEditorValidationChipState
    extends ConsumerState<CnlEditorValidationChip> {
  final _overlayController = OverlayPortalController();
  final _link = LayerLink();

  void _toggle() {
    setState(() {
      if (_overlayController.isShowing) {
        _overlayController.hide();
      } else {
        _overlayController.show();
      }
    });
  }

  void _close() {
    setState(() => _overlayController.hide());
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(_validationOverlaySummaryProvider);
    final parseErrors = summary.parseErrors;
    final validationResult = summary.validationResult;
    final layer1Failures = summary.layer1Failures;
    final layer2Failures = summary.layer2Failures;
    final totalErrors = parseErrors + layer1Failures + layer2Failures;
    final isRunning = summary.isRunning;

    if (!isRunning && totalErrors == 0 && validationResult != null) {
      // Hide any open popup when errors are cleared.
      if (_overlayController.isShowing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _overlayController.hide();
        });
      }
      return const SizedBox.shrink();
    }

    final hasErrors = totalErrors > 0;
    final colors = Zeta.of(context).colors;
    final isExpanded = _overlayController.isShowing;

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (ctx) => CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.bottomRight,
          offset: const Offset(0, -6),
          child: Align(
            alignment: Alignment.bottomRight,
            child: ValidationPopup(
              parseErrors: parseErrors,
              layer1Failures: layer1Failures,
              layer2Failures: layer2Failures,
              validationResult: validationResult,
              onClose: _close,
            ),
          ),
        ),
        child: _ValidationBadge(
          isRunning: isRunning,
          errorCount: totalErrors,
          expanded: isExpanded,
          hasErrors: hasErrors,
          colors: colors,
          onTap: hasErrors ? _toggle : null,
        ),
      ),
    );
  }
}

/// Floating validation badge + popup for the Architecture step.
///
/// Kept for reference but no longer inserted into the widget tree — the
/// Colored info-icon that sits in the CNL/NIR/Canvas picker row.
///
/// Hidden when the spec is valid. Shows [Icons.info_outline_rounded] in
/// the Zeta main-negative (red) when there are errors, or a subtle warning
/// tint while validation is running. Tapping opens a floating [ValidationPopup]
/// anchored above-right of the icon.
class ValidationStatusIcon extends ConsumerStatefulWidget {
  const ValidationStatusIcon({super.key});

  @override
  ConsumerState<ValidationStatusIcon> createState() =>
      _ValidationStatusIconState();
}

class _ValidationStatusIconState extends ConsumerState<ValidationStatusIcon> {
  final _overlayController = OverlayPortalController();
  final _link = LayerLink();

  void _toggle() {
    if (_overlayController.isShowing) {
      _overlayController.hide();
    } else {
      _overlayController.show();
    }
  }

  void _close() => _overlayController.hide();

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(_validationOverlaySummaryProvider);
    final parseErrors = summary.parseErrors;
    final layer1Failures = summary.layer1Failures;
    final layer2Failures = summary.layer2Failures;
    final totalErrors = parseErrors + layer1Failures + layer2Failures;
    final isRunning = summary.isRunning;

    // When issues resolve, keep OverlayPortal mounted while popup is still
    // open so the controller stays attached (calling hide() on a detached
    // controller asserts _zOrderIndex != null). Once the popup is closed the
    // widget will naturally collapse on the next rebuild.
    if (!isRunning && totalErrors == 0 && summary.validationResult != null) {
      if (!_overlayController.isShowing) {
        return const SizedBox.shrink();
      }
      // Fall through — render the portal so we can close it safely below.
    }

    final colors = Zeta.of(context).colors;
    final color = isRunning ? colors.mainSubtle : colors.mainNegative;
    final tooltipMsg = isRunning
        ? 'Validating…'
        : '$totalErrors issue${totalErrors == 1 ? '' : 's'}';

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (ctx) => CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.bottomRight,
          offset: const Offset(0, -6),
          child: Align(
            alignment: Alignment.bottomRight,
            child: ValidationPopup(
              parseErrors: parseErrors,
              layer1Failures: layer1Failures,
              layer2Failures: layer2Failures,
              validationResult: summary.validationResult,
              onClose: _close,
            ),
          ),
        ),
        child: Tooltip(
          message: tooltipMsg,
          child: IconButton(
            icon: Icon(
              isRunning
                  ? Icons
                        .hourglass_top_rounded // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                  : ZetaIcons.info,
              size: 18,
              color: color,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: totalErrors > 0 ? _toggle : null,
          ),
        ),
      ),
    );
  }
}

/// [CnlEditorValidationChip] embedded in the CNL editor toolbar row replaces
/// it. Can be removed once confirmed that nothing else references it.
class ValidationOverlay extends ConsumerStatefulWidget {
  const ValidationOverlay({super.key});

  @override
  ConsumerState<ValidationOverlay> createState() => _ValidationOverlayState();
}

class _ValidationOverlayState extends ConsumerState<ValidationOverlay> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(_validationOverlaySummaryProvider);
    final parseErrors = summary.parseErrors;
    final validationResult = summary.validationResult;
    final layer1Failures = summary.layer1Failures;
    final layer2Failures = summary.layer2Failures;
    final totalErrors = parseErrors + layer1Failures + layer2Failures;
    final hasErrors = totalErrors > 0;

    // Show only when there are active errors — hidden while running or valid.
    if (!hasErrors) return const SizedBox.shrink();

    final colors = Zeta.of(context).colors;

    return Positioned(
      right: 16,
      top: 80,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_expanded)
            ValidationPopup(
              parseErrors: parseErrors,
              layer1Failures: layer1Failures,
              layer2Failures: layer2Failures,
              validationResult: validationResult,
              onClose: () => setState(() => _expanded = false),
            ),
          if (_expanded) const SizedBox(height: 8),
          _ValidationCircleBadge(
            colors: colors,
            onTap: () => setState(() => _expanded = !_expanded),
          ),
        ],
      ),
    );
  }
}

/// Compact circular badge used by [ValidationOverlay].
/// Shows only when there are active errors; tap toggles the popup.
class _ValidationCircleBadge extends StatelessWidget {
  const _ValidationCircleBadge({required this.colors, required this.onTap});

  final ZetaColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: colors.surfaceWarning,
        shape: const CircleBorder(),
        elevation: 3,
        // ZETA-MIGRATION-EXEMPT: drop-shadow cast color — no Zeta semantic role for shadows
        shadowColor: Colors.black38,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Icon(
            ZetaIcons.warning_outline,
            size: 22,
            color: colors.mainWarning,
          ),
        ),
      ),
    );
  }
}

/// Full pill badge used by [CnlEditorValidationChip].
class _ValidationBadge extends StatelessWidget {
  const _ValidationBadge({
    required this.isRunning,
    required this.errorCount,
    required this.expanded,
    required this.hasErrors,
    required this.colors,
    required this.onTap,
  });

  final bool isRunning;
  final int errorCount;
  final bool expanded;
  final bool hasErrors;
  final ZetaColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bgColor = isRunning
        ? colors.surfaceDefault
        : hasErrors
        ? colors.surfaceWarning
        : colors.surfacePositive;
    final fgColor = isRunning
        ? colors.mainDefault
        : hasErrors
        ? colors.mainWarning
        : colors.mainPositive;
    final icon = isRunning
        ? Icons
              .hourglass_top_rounded // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
        : hasErrors
        ? ZetaIcons.warning_outline
        : ZetaIcons.check_circle_outline;
    final label = isRunning
        ? 'Validating…'
        : hasErrors
        ? '$errorCount issue${errorCount == 1 ? '' : 's'}'
        : 'Valid';

    return Material(
      // ZETA-MIGRATION-EXEMPT: transparent (no fill) — Zeta has no transparent token
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          NmtkShellTokens.of(context).radiusLg,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(
              NmtkShellTokens.of(context).radiusLg,
            ),
            border: Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                // ZETA-MIGRATION-EXEMPT: drop-shadow cast color — no Zeta semantic role for shadows
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fgColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: Zeta.of(context).textStyles.labelMedium.copyWith(
                  color: fgColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              if (hasErrors) ...[
                const SizedBox(width: 4),
                Icon(
                  expanded ? ZetaIcons.arrow_down : ZetaIcons.arrow_up,
                  size: 16,
                  color: fgColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ValidationPopup extends StatelessWidget {
  const ValidationPopup({
    super.key,
    required this.parseErrors,
    required this.layer1Failures,
    required this.layer2Failures,
    required this.validationResult,
    required this.onClose,
  });

  final int parseErrors;
  final int layer1Failures;
  final int layer2Failures;
  final ValidationResult? validationResult;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final maxWidth = MediaQuery.sizeOf(context).width - (tokens.sectionGap * 2);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;
    return Material(
      // ZETA-MIGRATION-EXEMPT: transparent (no fill) — Zeta has no transparent token
      color: Colors.transparent,
      child: Container(
        width: maxWidth.clamp(0, 340),
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(
            NmtkShellTokens.of(context).radiusSm,
          ),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              // ZETA-MIGRATION-EXEMPT: drop-shadow cast color — no Zeta semantic role for shadows
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PopupHeader(onClose: onClose),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (parseErrors > 0) ...[
                      _SectionHeader(
                        'Parse errors ($parseErrors)',
                        Icons
                            .code_off_rounded, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (layer1Failures > 0 && validationResult != null) ...[
                      _SectionHeader(
                        'Layer 1 failures ($layer1Failures)',
                        ZetaIcons.layers,
                      ),
                      const SizedBox(height: 8),
                      for (final item in validationResult!.layer1.failed)
                        _FailureItem(
                          title: item.name,
                          detail: item.message ?? '',
                        ),
                      const SizedBox(height: 12),
                    ],
                    if (layer2Failures > 0 && validationResult != null) ...[
                      _SectionHeader(
                        'Layer 2 failures ($layer2Failures)',
                        Icons
                            .account_tree_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                      ),
                      const SizedBox(height: 8),
                      for (final item in validationResult!.layer2.checksFailed)
                        _FailureItem(
                          title: item.primaryName ?? 'Check failed',
                          detail: item.primaryMessage ?? '',
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PopupHeader extends StatelessWidget {
  const _PopupHeader({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Icon(
            ZetaIcons.warning_outline,
            size: 18,
            color: Zeta.of(context).colors.mainNegative,
          ),
          const SizedBox(width: 8),
          Text(
            'Validation issues',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Tooltip(
            message: 'Dismiss',
            child: SizedBox(
              width: 44,
              height: 44,
              child: ZetaIconButton.text(
                onPressed: onClose,
                icon: ZetaIcons.close,
                size: ZetaWidgetSize.small,
                semanticLabel: 'Dismiss',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text, this.icon);
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _FailureItem extends StatelessWidget {
  const _FailureItem({required this.title, required this.detail});
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ZetaIcons.cancel_outline,
            size: 14,
            color: Zeta.of(context).colors.mainNegative,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (detail.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
