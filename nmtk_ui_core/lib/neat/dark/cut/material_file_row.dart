import 'package:flutter/material.dart';

/// One row inside [NewMaterialCard]: file icon placeholder + name + size +
/// download button placeholder.
class MaterialFileRow extends StatelessWidget {
  const MaterialFileRow({super.key, required this.name, required this.size});
  final String name, size;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 16,
      children: [
        const SizedBox(width: 48, height: 48),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  height: 1.43,
                ),
              ),
              Text(
                size,
                style: const TextStyle(
                  color: Color(0xFF808D9E),
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400,
                  height: 1.57,
                  letterSpacing: -0.50,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 36,
          height: 36,
          decoration: const ShapeDecoration(
            shape: OvalBorder(
              side: BorderSide(width: 2, color: Color(0xFF4B4C57)),
            ),
          ),
        ),
      ],
    );
  }
}
