import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/widgets/section_card.dart';

class NmtkProgressCard extends StatelessWidget {
  const NmtkProgressCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.progress,
    required this.statusIcon,
    required this.statusColor,
    required this.statusLabel,
    this.errorText,
    this.details = const <Widget>[],
    this.trailing,
  });

  final String title;
  final String subtitle;
  final double? progress;
  final IconData statusIcon;
  final Color statusColor;
  final String statusLabel;
  final String? errorText;
  final List<Widget> details;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return NmtkSectionCard(
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: progress,
            color: errorText != null ? Colors.red : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(statusIcon, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: errorText != null ? Colors.red : null,
                  ),
                ),
              ),
            ],
          ),
          if (errorText != null) ...[
            const SizedBox(height: 8),
            Text(errorText!, style: const TextStyle(color: Colors.red)),
          ],
          if (details.isNotEmpty) ...[const SizedBox(height: 8), ...details],
        ],
      ),
    );
  }
}
