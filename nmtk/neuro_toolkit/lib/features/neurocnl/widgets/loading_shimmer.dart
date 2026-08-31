// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class LoadingShimmer extends StatelessWidget {
  final double width;
  final double height;
  final double? borderRadius;

  const LoadingShimmer({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Zeta.of(context).colors.surfaceDefault,
      highlightColor: Zeta.of(
        context,
      ).colors.borderDefault.withValues(alpha: 0.5),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Zeta.of(context).colors.surfaceDefault,
          borderRadius: BorderRadius.circular(
            borderRadius ?? NmtkShellTokens.of(context).radiusSm,
          ),
        ),
      ),
    );
  }

  /// Shimmer for a list item (e.g. template, table row).
  static Widget listTile({double height = 56}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          LoadingShimmer(width: height, height: height),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LoadingShimmer(width: double.infinity, height: height * 0.3),
                const SizedBox(height: 4),
                LoadingShimmer(width: 150, height: height * 0.2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Shimmer for a large panel (e.g. chart, editor).
  static Widget panel({double height = 200}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LoadingShimmer(width: 120, height: 20),
        const SizedBox(height: 12),
        LoadingShimmer(width: double.infinity, height: height),
      ],
    );
  }
}
