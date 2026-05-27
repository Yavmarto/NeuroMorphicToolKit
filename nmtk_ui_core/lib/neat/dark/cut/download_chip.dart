import 'package:flutter/material.dart';

/// Blue "Download Report" chip used next to the [FilterChip] in
/// [OverviewChartCard].
class DownloadChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: ShapeDecoration(
        color: const Color(0x192A85FF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: const Text('Download Report', style: TextStyle(color: Color(0xFF2180FF), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43)),
    );
  }
}
