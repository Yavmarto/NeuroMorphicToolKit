import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_status_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_top_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/health_widgets.dart';

class NeatHealth extends StatelessWidget {
  @Preview(name: 'Neat Dark – Health', group: 'Neat Dark Pages', size: Size(375, 1430))
  const NeatHealth({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 375,
          height: 1430,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
          child: const Stack(
            children: [
              Positioned(left: 0, top: 0, child: DarkStatusBar()),
              Positioned(left: 0, top: 44, child: DarkTopBar()),
              Positioned(left: 16, top: 156, child: HealthMetricCard(color: Color(0xFF8E59FF), label: 'PULSE', value: '98.2', unit: 'bpm')),
              Positioned(left: 196, top: 156, child: HealthMetricCard(color: Color(0xFF2180FF), label: 'TEMPERATURE', value: '37.1', unit: '°C')),
              Positioned(left: 16, top: 346, child: OximeterCard()),
              Positioned(left: 196, top: 346, child: HealthMetricCard(color: Color(0xFF60D39C), label: 'WEIGHT', value: '65.6', unit: 'kg')),
              Positioned(left: 16, top: 536, child: SpirometryCard()),
              Positioned(left: 16, top: 1002, child: _TempLogSection()),
            ],
          ),
        ),
      ],
    );
  }
}

class _TempLogSection extends StatelessWidget {
  const _TempLogSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text('Aug 22, 2022', style: TextStyle(color: Color(0xFF808D9E), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43)),
        TempLogRow(level: 'Normal', levelColor: Color(0xFF2180FF), levelBg: Color(0x190062FF)),
        SizedBox(height: 16),
        Text('Aug 23, 2022', style: TextStyle(color: Color(0xFF808D9E), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43)),
        TempLogRow(level: 'High', levelColor: Color(0xFFFF5555), levelBg: Color(0x19FF0000)),
        SizedBox(height: 16),
        Text('Aug 24, 2022', style: TextStyle(color: Color(0xFF808D9E), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43)),
        TempLogRow(level: 'Medium', levelColor: Color(0xFFFFC14B), levelBg: Color(0x19FFC24B)),
      ],
    );
  }
}
