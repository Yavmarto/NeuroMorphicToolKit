import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

class NmtkKeyValueRow extends StatelessWidget {
  const NmtkKeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.padding = const EdgeInsets.only(bottom: 6),
    this.valueColor,
  });

  final String label;
  final String value;
  final EdgeInsetsGeometry padding;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final zeta = Zeta.of(context);

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: zeta.textStyles.bodySmall.copyWith(
                color: zeta.colors.mainSubtle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: zeta.textStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: valueColor ?? zeta.colors.mainPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
