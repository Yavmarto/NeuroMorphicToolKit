part of '../module_picker_panel.dart';

class _ModuleActivityState extends StatelessWidget {
  final String label;
  final NmtkTone tone;

  const _ModuleActivityState({required this.label, this.tone = NmtkTone.info});

  @override
  Widget build(BuildContext context) {
    return NmtkSurfaceCard(
      tone: tone,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: ZetaProgressCircle(size: ZetaCircleSizes.xs),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
