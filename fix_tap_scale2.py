with open('nmtk_ui_core/lib/motion_tokens.dart', 'r') as f:
    text = f.read()

old_build = """  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(scale: _scaleAnimation, child: widget.child),
    );
  }"""

new_build = """  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      onTapDown: disableAnimations ? null : _onTapDown,
      onTapUp: disableAnimations ? null : _onTapUp,
      onTapCancel: disableAnimations ? null : _onTapCancel,
      child: disableAnimations ? widget.child : ScaleTransition(scale: _scaleAnimation, child: widget.child),
    );
  }"""

text = text.replace(old_build, new_build)

with open('nmtk_ui_core/lib/motion_tokens.dart', 'w') as f:
    f.write(text)

print("Updated motion_tokens.dart (TapScaleWrapper)")
