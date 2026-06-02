import 'package:flutter/material.dart';

/// Big number + unit (e.g. "66 Kg") used inside [WeightProgressSection].
/// [label] is currently unused visually but kept on the public API for
/// callers that pass a description.
class WeightStat extends StatelessWidget {
  const WeightStat({
    super.key,
    required this.value,
    required this.unit,
    required this.label,
  });
  final String value, unit, label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 36,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            height: 1.17,
            letterSpacing: -0.36,
          ),
        ),
        Text(
          unit,
          style: const TextStyle(
            color: Color(0xFFE9ECF2),
            fontSize: 14,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w400,
            height: 1.57,
            letterSpacing: -0.50,
          ),
        ),
      ],
    );
  }
}
