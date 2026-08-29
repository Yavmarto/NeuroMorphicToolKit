import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

class ShellPanel extends StatelessWidget {
  const ShellPanel({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.onHide,
    this.padding = EdgeInsets.zero,
    this.borderRadius = BorderRadius.zero,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onHide;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);

    return Container(
      decoration: BoxDecoration(
        color: tokens.utilityPanelBackground,
        borderRadius: borderRadius,
        border: Border.all(color: tokens.chromeBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(padding: padding, child: child),
          ),
        ],
      ),
    );
  }
}
