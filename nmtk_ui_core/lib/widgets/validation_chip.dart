import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';

const Duration _kExpandCollapseDuration = Duration(milliseconds: 220);
const Duration _kFadeInDelay = Duration(milliseconds: 40);
const Duration _kValidFadeOutDuration = Duration(milliseconds: 400);
const Duration _kValidAutoHideDelay = Duration(seconds: 3);

/// A single validation error entry shown in the expanded list.
class NmtkValidationError {
  const NmtkValidationError({required this.message, this.line});

  /// Human-readable error description.
  final String message;

  /// Optional 1-based line number associated with the error.
  final int? line;
}

/// Collapsible validation summary chip.
///
/// - When [errorCount] > 0: shows a red pill "✗ N error(s)" and expands on
///   tap to reveal the full error list.
/// - When [errorCount] == 0: shows a green "✓ Valid" pill that automatically
///   fades out after 3 seconds.
///
/// This widget is state-management-agnostic (callback-based, no
/// Provider/Riverpod dependency).
class NmtkValidationChip extends StatefulWidget {
  const NmtkValidationChip({
    super.key,
    required this.errorCount,
    this.errors = const [],
    this.onNavigateToError,
  });

  /// Total number of validation errors.
  final int errorCount;

  /// Detailed error list shown when the chip is expanded.
  final List<NmtkValidationError> errors;

  /// Called with the error index when F8 cycles through errors.
  final ValueChanged<int>? onNavigateToError;

  @override
  State<NmtkValidationChip> createState() => _NmtkValidationChipState();
}

class _NmtkValidationChipState extends State<NmtkValidationChip> {
  bool _expanded = false;
  bool _listVisible = false;
  bool _chipVisible = true; // false when the "valid" chip has faded out
  Timer? _validTimer;
  Timer? _listFadeTimer;

  // Tracks which error index will be navigated to on the next F8 press.
  int _f8Index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.errorCount == 0) {
      _scheduleValidAutoHide();
    }
  }

  @override
  void didUpdateWidget(NmtkValidationChip oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.errorCount != oldWidget.errorCount) {
      if (widget.errorCount > 0) {
        // Errors arrived — cancel any pending "valid" hide, show chip.
        _cancelValidTimer();
        if (!_chipVisible) {
          setState(() => _chipVisible = true);
        }
        // Collapse the list when error count changes to let user re-open.
        _collapseList(immediate: true);
        _f8Index = 0;
      } else {
        // Errors cleared — collapse, schedule auto-hide.
        _collapseList(immediate: true);
        setState(() => _chipVisible = true);
        _scheduleValidAutoHide();
      }
    }
  }

  @override
  void dispose() {
    _cancelValidTimer();
    _cancelListFadeTimer();
    super.dispose();
  }

  void _scheduleValidAutoHide() {
    _cancelValidTimer();
    _validTimer = Timer(_kValidAutoHideDelay, () {
      if (mounted) setState(() => _chipVisible = false);
    });
  }

  void _cancelValidTimer() {
    _validTimer?.cancel();
    _validTimer = null;
  }

  void _cancelListFadeTimer() {
    _listFadeTimer?.cancel();
    _listFadeTimer = null;
  }

  void _toggleExpanded() {
    if (widget.errorCount == 0) return;
    if (_expanded) {
      _collapseList();
    } else {
      _expandList();
    }
  }

  void _expandList() {
    setState(() {
      _expanded = true;
      _listVisible = false;
    });
    _cancelListFadeTimer();
    _listFadeTimer = Timer(_kFadeInDelay, () {
      if (mounted) setState(() => _listVisible = true);
    });
  }

  void _collapseList({bool immediate = false}) {
    _cancelListFadeTimer();
    if (immediate) {
      setState(() {
        _expanded = false;
        _listVisible = false;
      });
    } else {
      setState(() {
        _expanded = false;
        _listVisible = false;
      });
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape && _expanded) {
      _collapseList();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.f8 &&
        widget.errorCount > 0 &&
        widget.onNavigateToError != null) {
      widget.onNavigateToError!(_f8Index % widget.errorCount);
      _f8Index = (_f8Index + 1) % widget.errorCount;
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final hasErrors = widget.errorCount > 0;

    // When in valid state and chip has faded out, render nothing.
    if (!hasErrors && !_chipVisible) {
      return const SizedBox.shrink();
    }

    ZetaColors? colors;
    try {
      colors = Zeta.of(context).colors;
    } catch (_) {}

    final tokens = NmtkShellTokens.of(context);

    final fg = colors != null
        ? (hasErrors ? colors.mainNegative : colors.mainPositive)
        : (hasErrors
            ? tokens.errorColor
            : tokens.healthyColor);

    final bg = colors != null
        ? (hasErrors ? colors.surfaceNegativeSubtle : colors.surfacePositiveSubtle)
        : (hasErrors
            ? tokens.errorColor.withOpacity(0.12)
            : tokens.healthyColor.withOpacity(0.12));

    final border = colors != null
        ? (hasErrors ? colors.borderNegative : colors.borderPositive)
        : (hasErrors
            ? tokens.errorColor.withOpacity(0.5)
            : tokens.healthyColor.withOpacity(0.5));

    final errorLabel = widget.errorCount == 1
        ? '✗ 1 error'
        : '✗ ${widget.errorCount} errors';
    final chipLabel = hasErrors ? errorLabel : '✓ Valid';
    final chipIcon = hasErrors
        ? Icons.cancel_outlined
        : Icons.check_circle_outline;

    final pill = GestureDetector(
      onTap: hasErrors ? _toggleExpanded : null,
      child: AnimatedOpacity(
        opacity: hasErrors ? 1.0 : (_chipVisible ? 1.0 : 0.0),
        duration: _kValidFadeOutDuration,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(tokens.radiusChip),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(chipIcon, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(
                chipLabel,
                style: TextStyle(
                  fontSize: 13,
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (hasErrors) ...[
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: _kExpandCollapseDuration,
                  child: Icon(Icons.keyboard_arrow_down, size: 14, color: fg),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return Focus(
      onKeyEvent: _handleKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          pill,
          AnimatedSize(
            duration: _kExpandCollapseDuration,
            curve: Curves.easeInOut,
            alignment: Alignment.topLeft,
            child: _expanded
                ? AnimatedOpacity(
                    opacity: _listVisible ? 1.0 : 0.0,
                    duration: _kExpandCollapseDuration,
                    child: _ErrorDropdown(errors: widget.errors),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ── Error dropdown card ───────────────────────────────────────────────────

class _ErrorDropdown extends StatelessWidget {
  const _ErrorDropdown({required this.errors});

  final List<NmtkValidationError> errors;

  @override
  Widget build(BuildContext context) {
    ZetaColors? colors;
    try {
      colors = Zeta.of(context).colors;
    } catch (_) {}

    final tokens = NmtkShellTokens.of(context);

    final bg = colors != null
        ? colors.surfaceNegativeSubtle
        : tokens.errorColor.withOpacity(0.12);

    final border = colors != null
        ? colors.borderNegative
        : tokens.errorColor.withOpacity(0.5);

    final fg = colors != null
        ? colors.mainNegative
        : tokens.errorColor;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: errors.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: border),
          itemBuilder: (context, index) {
            final error = errors[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (error.line != null) ...[
                    Text(
                      'L${error.line}',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: fg,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      error.message,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
