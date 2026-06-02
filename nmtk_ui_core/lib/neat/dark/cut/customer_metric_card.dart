import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// Hero metric card on the customer dashboard (large value + label + delta).
class CustomerMetricCard extends StatelessWidget {
  const CustomerMetricCard({
    super.key,
    required this.value,
    required this.label,
    required this.change,
  });
  final String value, label, change;

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
          borderRadius: BorderRadius.circular(
            NmtkShellTokens.of(context).radiusSm,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 24,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const ShapeDecoration(
              color: Colors.white,
              shape: OvalBorder(
                side: BorderSide(width: 2, color: Color(0xFFE9ECF2)),
              ),
            ),
          ),
          const SizedBox(width: 24, height: 24),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              height: 1.17,
              letterSpacing: -0.36,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              SizedBox(
                width: 219,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF808D9E),
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                    height: 1.57,
                    letterSpacing: -0.50,
                  ),
                ),
              ),
              Text(
                change,
                style: const TextStyle(
                  color: Color(0xFF60D39C),
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  height: 1.43,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
