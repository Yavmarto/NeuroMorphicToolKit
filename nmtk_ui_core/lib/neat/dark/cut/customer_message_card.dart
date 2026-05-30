import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_card_header.dart';
import 'package:nmtk_ui_core/neat/dark/cut/message_row.dart';

/// "Message" card listing recent customer DMs plus a "See All" footer.
class CustomerMessageCard extends StatelessWidget {
  const CustomerMessageCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 343,
      padding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 24,
        children: [
          const DarkCardHeader(title: 'Message', iconColor: Color(0xFFB0E5FC)),
          const MessageRow(name: 'Alex Frunish', handle: '@alex', preview: 'Hi There! Let\'s go trip 🏄‍♂️', time: '2 mins'),
          const MessageRow(name: 'Rakabuming Suhu', handle: '@suhu', preview: 'Bro, ayo ngopi sor sawo..', time: '30 mins'),
          const MessageRow(name: 'Cinta Faradhiba', handle: '@fara', preview: 'Dikasih info maszehhhh!!!!', time: 'Yesterday'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: ShapeDecoration(
              color: const Color(0xFF1D1D25),
              shape: RoundedRectangleBorder(
                side: const BorderSide(width: 2, color: Color(0xFF4B4C57)),
                borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Text('See All Message', style: TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25))],
            ),
          ),
        ],
      ),
    );
  }
}
