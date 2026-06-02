import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// Blue "Download Report" chip used next to the [FilterChip] in
/// [OverviewChartCard].
class DownloadChip extends StatelessWidget {
  const DownloadChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: ShapeDecoration(
        color: const Color(0x192A85FF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            NmtkShellTokens.of(context).radiusSm,
          ),
        ),
      ),
      child: const Text(
        'Download Report',
        style: TextStyle(
          color: Color(0xFF2180FF),
          fontSize: 14,
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          height: 1.43,
        ),
      ),
    );
  }
}
