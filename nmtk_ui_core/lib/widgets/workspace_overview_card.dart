import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/widgets/surface_card.dart';

class NmtkWorkspaceOverviewCard extends StatelessWidget {
  const NmtkWorkspaceOverviewCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.message,
    this.trailing,
    this.chips = const <Widget>[],
  });

  final String title;
  final String subtitle;
  final String message;
  final Widget? trailing;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return NmtkSurfaceCard(
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (chips.isNotEmpty) ...[
            Wrap(spacing: 8, runSpacing: 8, children: chips),
            const SizedBox(height: 16),
          ],
          Text(message, style: Zeta.of(context).textStyles.bodyMedium),
        ],
      ),
    );
  }
}
