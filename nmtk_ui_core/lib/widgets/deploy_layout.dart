import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/widgets/section.dart';

/// A standard two-pane platform deployment layout.
///
/// Places inference, simulation, and execution controls on the left
/// (flexible/expanded), and deployment setup, host configuration, parameters,
/// and deploy actions on the right (fixed width, default 360 px).
///
/// On screens narrower than [NmtkShellTokens.normalBreakpoint] or when
/// [isCompact] is true, the layout stacks vertically with setup on top and
/// inference below.
class NmtkDeployLayout extends StatelessWidget {
  const NmtkDeployLayout({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
    required this.inference,
    required this.setup,
    this.setupWidth = 360.0,
    this.gap = 24.0,
    this.isCompact = false,
    this.titleStyle,
  });

  /// Headline title for the deployment section.
  final String title;

  /// Optional leading widget in the section header.
  final Widget? leading;

  /// Optional trailing widget in the section header (e.g. status badge).
  final Widget? trailing;

  /// The main inference / execution / simulation / visualization surface (left side).
  final Widget inference;

  /// The deployment setup / host / hardware / parameter configuration surface (right side).
  final Widget setup;

  /// Width of the setup pane in side-by-side mode. Defaults to 360 px.
  final double setupWidth;

  /// Gap between the inference and setup panes. Defaults to 24 px.
  final double gap;

  /// Explicit compact flag, e.g. for drawer or mobile contexts.
  final bool isCompact;

  /// Optional title text style override.
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    return NmtkSection(
      title: title,
      leading: leading,
      trailing: trailing,
      titleStyle: titleStyle,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow =
              isCompact ||
              constraints.maxWidth < NmtkShellTokens.normalBreakpoint;

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                setup,
                SizedBox(height: gap),
                inference,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: inference),
              SizedBox(width: gap),
              SizedBox(width: setupWidth, child: setup),
            ],
          );
        },
      ),
    );
  }
}
