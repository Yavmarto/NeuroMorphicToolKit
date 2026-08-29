import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// Rebuild-safe wrapper for [ZetaTextInput] when the parent owns the value.
///
/// Zeta 1.4.5 resets the inner controller text from `initialValue` during
/// `didUpdateWidget`, which can disturb caret/selection state if the parent
/// rebuilds on each keystroke. This wrapper keeps the initial value stable
/// while focused and only accepts external value changes when the field is not
/// being edited.
class StableZetaTextInput extends StatefulWidget {
  const StableZetaTextInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.hintText,
    this.keyboardType,
    this.disabled = false,
    this.prefix,
    this.suffix,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? hintText;
  final TextInputType? keyboardType;
  final bool disabled;
  final Widget? prefix;
  final Widget? suffix;

  @override
  State<StableZetaTextInput> createState() => _StableZetaTextInputState();
}

class _StableZetaTextInputState extends State<StableZetaTextInput> {
  late final FocusNode _focusNode;
  late String _stableInitialValue;
  late String _lastValue;

  @override
  void initState() {
    super.initState();
    _stableInitialValue = widget.value;
    _lastValue = widget.value;
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant StableZetaTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusNode.hasFocus) {
      return;
    }
    if (oldWidget.value != widget.value && _lastValue != widget.value) {
      _stableInitialValue = widget.value;
      _lastValue = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ZetaTextInput(
      initialValue: _stableInitialValue,
      focusNode: _focusNode,
      label: widget.label,
      hintText: widget.hintText,
      keyboardType: widget.keyboardType,
      disabled: widget.disabled,
      prefix: widget.prefix,
      suffix: widget.suffix,
      onChange: (String? value) {
        if (value == null || widget.disabled) {
          return;
        }
        _lastValue = value;
        widget.onChanged(value);
      },
    );
  }
}
