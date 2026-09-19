part of '../environment_editor.dart';

class _BusyBanner extends StatelessWidget {
  const _BusyBanner({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final zeta = Zeta.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: context.nmtkTokens.sectionGap * 1.5,
        vertical: context.nmtkTokens.compactGap,
      ),
      color: zeta.colors.surfaceInfoSubtle,
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: ZetaProgressCircle(size: ZetaCircleSizes.xs),
          ),
          SizedBox(width: context.nmtkTokens.compactGap),
          Text(label, style: Zeta.of(context).textStyles.bodyMedium),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _EnvironmentCard — one card per environment, expandable to manage packages.
//
// Package state is owned by [environmentPackageProvider] (family by slug),
// eliminating the four setState calls that tracked loading/packages/error.
// ---------------------------------------------------------------------------
