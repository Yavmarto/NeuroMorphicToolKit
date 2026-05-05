with open('nmtk_ui_core/lib/motion_tokens.dart', 'r') as f:
    text = f.read()

old_build = """  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (!widget.isPulsing) return dot;
    return ScaleTransition(scale: _pulseAnimation, child: dot);
  }"""

new_build = """  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    if (!widget.isPulsing || disableAnimations) return dot;
    return ScaleTransition(scale: _pulseAnimation, child: dot);
  }"""

text = text.replace(old_build, new_build)

with open('nmtk_ui_core/lib/motion_tokens.dart', 'w') as f:
    f.write(text)

print("Updated motion_tokens.dart (StatusDot)")
