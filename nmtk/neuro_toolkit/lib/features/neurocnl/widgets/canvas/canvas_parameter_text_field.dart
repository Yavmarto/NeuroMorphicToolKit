import 'dart:async';

import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Debounced text field for canvas/NIR parameter editing.
///
/// Commits via [onCommit] on blur, editing complete, or after [commitDebounce]
/// while typing.
///
/// Uses a stable [initialValue] strategy instead of a shared
/// TextEditingController to avoid the ZetaTextFormField.didUpdateWidget cursor
/// reset that fires whenever [initialValue] changes between builds.  The
/// stable value only advances when the field is NOT focused and the external
/// [value] prop changes.
class CanvasParameterTextField extends StatefulWidget {
  const CanvasParameterTextField({
    super.key,
    required this.label,
    required this.value,
    required this.onCommit,
    this.keyboardType,
    this.enabled = true,
    this.commitDebounce = const Duration(milliseconds: 200),
    this.showLabel = true,
    this.hintText,
    this.placeholder,
    this.onSubmitted,
    this.errorText,
    this.suffix,
  });

  final String label;
  final String value;
  final ValueChanged<String> onCommit;
  final TextInputType? keyboardType;
  final bool enabled;
  final Duration commitDebounce;

  /// When false, only the input is shown (label supplied by [LabeledParameterRow]).
  final bool showLabel;

  /// Optional help text shown *below* the field. Zeta calls this `hintText`;
  /// the greyed text *inside* the field is [placeholder].
  final String? hintText;

  /// Greyed sample value shown inside the empty field.
  final String? placeholder;

  /// Called when the user presses Enter, after the pending edit is committed.
  /// Lets a field drive its own action instead of forcing a trip to a button.
  final VoidCallback? onSubmitted;

  /// Validation message shown under the field.
  final String? errorText;

  /// Optional widget to display at the trailing edge of the text field.
  final Widget? suffix;

  @override
  State<CanvasParameterTextField> createState() =>
      _CanvasParameterTextFieldState();
}

class _CanvasParameterTextFieldState extends State<CanvasParameterTextField> {
  late final FocusNode _focusNode;
  Timer? _debounce;
  // Stable initialValue for ZetaTextInput — only updated while NOT focused.
  // Keeping it constant while the user types prevents ZetaTextFormFieldState
  // .didUpdateWidget from resetting the cursor (it resets when initialValue
  // differs between consecutive builds, which ZetaTextFormField derives from
  // controller.text at construction time).
  late String _stableInitialValue;
  // Last text value as reported by ZetaTextInput.onChange; used for commits.
  late String _lastValue;
  String _lastCommitted = '';

  @override
  void initState() {
    super.initState();
    _stableInitialValue = widget.value;
    _lastValue = widget.value;
    _lastCommitted = widget.value;
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant CanvasParameterTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusNode.hasFocus) return;

    if (oldWidget.value != widget.value && _lastValue != widget.value) {
      _stableInitialValue = widget.value;
      _lastValue = widget.value;
      _lastCommitted = widget.value;
    }
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _flushCommit();
    }
  }

  void _scheduleCommit(String text) {
    _debounce?.cancel();
    _debounce = Timer(widget.commitDebounce, () {
      if (!mounted) return;
      _commitIfChanged(text);
    });
  }

  void _flushCommit() {
    _debounce?.cancel();
    _commitIfChanged(_lastValue);
  }

  void _commitIfChanged(String text) {
    if (text == _lastCommitted) return;
    _lastCommitted = text;
    widget.onCommit(text);
  }

  // Flush on teardown, not just cancel: selecting another node, closing the
  // Inspector or advancing the stepper tears this widget down, and a value
  // typed inside the debounce window was silently discarded.
  //
  // `deactivate`, not `dispose`: `onCommit` reaches a provider through the
  // enclosing ConsumerWidget's `ref`, which is only usable while this element
  // is still attached to the tree. `_commitIfChanged` dedupes against
  // `_lastCommitted`, so a value already committed on blur is not re-sent and
  // a deactivate/reactivate (GlobalKey move) commits nothing.
  @override
  void deactivate() {
    _flushCommit();
    super.deactivate();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final input = NmtkTextInput(
      initialValue: _stableInitialValue,
      focusNode: _focusNode,
      disabled: !widget.enabled,
      keyboardType: widget.keyboardType,
      hintText: widget.hintText,
      placeholder: widget.placeholder,
      errorText: widget.errorText,
      suffix: widget.suffix,
      onChange: (String? value) {
        if (value == null || !widget.enabled) return;
        _lastValue = value;
        _scheduleCommit(value);
      },
      onFieldSubmitted: widget.onSubmitted == null
          ? null
          : (_) {
              _flushCommit();
              widget.onSubmitted!();
            },
    );

    if (!widget.showLabel) return input;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            widget.label,
            style: const TextStyle(
              color: NmtkNeurocnlTokens.textSecondary,
              fontSize: 11,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: input),
      ],
    );
  }
}

String displayCanvasParameterValue(Object? value) {
  if (value is double) {
    final String raw = value
        .toStringAsFixed(value.truncateToDouble() == value ? 1 : 6)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '.0');
    return raw;
  }
  return value?.toString() ?? '';
}
