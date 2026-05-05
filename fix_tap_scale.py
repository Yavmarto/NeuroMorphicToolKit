with open('nmtk_ui_core/lib/motion_tokens.dart', 'r') as f:
    text = f.read()

old_build = """  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.enabled ? widget.onTap : null,
      child: ScaleTransition(scale: _scaleAnimation, child: widget.child),
    );
  }"""

if old_build not in text:
    # Need to find the actual build method
    pass

