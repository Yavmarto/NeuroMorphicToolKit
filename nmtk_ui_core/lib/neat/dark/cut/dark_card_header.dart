import 'package:flutter/material.dart';

/// Card header row with a colored rounded icon circle (42×42) and a title.
/// Used across all dark Neat card sections.
class DarkCardHeader extends StatelessWidget {
  const DarkCardHeader({
    super.key,
    required this.title,
    required this.iconColor,
  });

  final String title;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 377,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: 16,
            children: [
              Container(
                width: 42,
                height: 42,
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(
                  color: iconColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Stack(
                  children: [
                    Positioned(
                      left: 9,
                      top: 9,
                      child: SizedBox(width: 24, height: 24),
                    ),
                  ],
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
