import 'package:flutter/material.dart';

/// One row inside [CustomerMessageCard]: avatar, name/handle, time and preview.
class MessageRow extends StatelessWidget {
  const MessageRow({
    super.key,
    required this.name,
    required this.handle,
    required this.preview,
    required this.time,
  });
  final String name, handle, preview, time;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const ShapeDecoration(
            color: Color(0xFFE9ECF2),
            shape: OvalBorder(),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    spacing: 4,
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
                        handle,
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
                  Text(
                    time,
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
              Text(
                preview,
                style: const TextStyle(
                  color: Colors.white,
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
      ],
    );
  }
}
