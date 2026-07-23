import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

/// Rebuild-safe wrapper for [ZetaTextInput].
/// Zeta 1.4.5 resets the inner controller text from `initialValue` (or the passed `controller`)
/// during `didUpdateWidget`, which can disturb caret/selection state if the parent
/// rebuilds on each keystroke. This wrapper keeps the initial value stable
/// while focused and only accepts external value changes when the field is not
/// being edited.
class NmtkTextInput extends StatefulWidget {
  const NmtkTextInput({
    super.key,
    this.controller,
    this.initialValue,
    this.onChange,
    this.onFieldSubmitted,
    this.keyboardType,
    this.obscureText = false,
    this.maxLines,
    this.minLines,
    this.disabled = false,
    this.focusNode,
    this.hintText,
    this.placeholder,
    this.label,
    this.prefix,
    this.suffix,
    this.errorText,
    this.validator,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String?>? onChange;
  final ValueChanged<String?>? onFieldSubmitted;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int? maxLines;
  final int? minLines;
  final bool disabled;
  final FocusNode? focusNode;
  final String? hintText;
  final String? placeholder;
  final String? label;
  final Widget? prefix;
  final Widget? suffix;
  final String? errorText;
  final FormFieldValidator<String>? validator;

  @override
  State<NmtkTextInput> createState() => _NmtkTextInputState();
}

class _NmtkTextInputState extends State<NmtkTextInput> {
  late FocusNode _focusNode;
  late String _stableInitialValue;
  late String _lastValue;

  @override
  void initState() {
    super.initState();
    final initial = widget.controller?.text ?? widget.initialValue ?? '';
    _stableInitialValue = initial;
    _lastValue = initial;
    _focusNode = widget.focusNode ?? FocusNode();
    widget.controller?.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (_focusNode.hasFocus) return;
    final newText = widget.controller?.text ?? '';
    if (_lastValue != newText) {
      setState(() {
        _stableInitialValue = newText;
        _lastValue = newText;
      });
    }
  }

  @override
  void didUpdateWidget(covariant NmtkTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
    }
    
    if (oldWidget.focusNode != widget.focusNode) {
      if (oldWidget.focusNode == null) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode();
    }

    if (_focusNode.hasFocus) return;
    
    final newText = widget.controller?.text ?? widget.initialValue ?? '';
    if ((oldWidget.initialValue != widget.initialValue || oldWidget.controller != widget.controller) && _lastValue != newText) {
      _stableInitialValue = newText;
      _lastValue = newText;
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ZetaTextInput(
      initialValue: _stableInitialValue,
      focusNode: _focusNode,
      label: widget.label,
      hintText: widget.hintText,
      placeholder: widget.placeholder,
      keyboardType: widget.keyboardType,
      obscureText: widget.obscureText,
      // maxLines/minLines aren't forwarded: zeta_flutter 1.4.5's
      // ZetaTextInput has no such parameters. Kept on this widget's own API
      // so callers don't break; currently a no-op until Zeta adds support.
      disabled: widget.disabled,
      prefix: widget.prefix,
      suffix: widget.suffix,
      errorText: widget.errorText,
      onChange: (String? value) {
        if (value == null || widget.disabled) return;
        _lastValue = value;
        widget.onChange?.call(value);
        if (widget.controller != null && widget.controller!.text != value) {
          widget.controller!.removeListener(_onControllerChanged);
          widget.controller!.text = value;
          widget.controller!.addListener(_onControllerChanged);
        }
      },
      onFieldSubmitted: widget.onFieldSubmitted,
    );
  }
}
