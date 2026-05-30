import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_status_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_top_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/office_widgets.dart';

class NeatOffice extends StatelessWidget {
  @Preview(name: 'Neat Dark – Office', group: 'Neat Dark Pages', size: Size(375, 1350))
  const NeatOffice({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 375,
          height: 1350,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
          child: const Stack(
            children: [
              Positioned(left: 0, top: 0, child: DarkStatusBar()),
              Positioned(left: 0, top: 44, child: DarkTopBar()),
              Positioned(
                left: 20, top: 176,
                child: SizedBox(width: 335, child: Text('Get in touch with us\nfor collaboration', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 24, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25))),
              ),
              Positioned(
                left: 41, top: 248,
                child: SizedBox(width: 293, child: Text('We help people to grow their business using Neat Dashboard ui kit with professional and powerfull digital solution.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF808D9E), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.57, letterSpacing: -0.50))),
              ),
              Positioned(left: 16, top: 338, child: OfficeCard(officeName: 'Head Quarter', location: 'United States', address: '183 S 18th St B, East Orange, US', phone: '+1 601-292-6500')),
              Positioned(left: 16, top: 846, child: OfficeCard(officeName: 'Second Office', location: 'Ponorogo', address: 'Bancangan, Sambit, Ponorogo', phone: '+1 601-292-6500')),
            ],
          ),
        ),
      ],
    );
  }
}
