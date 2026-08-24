part of '../module_picker_panel.dart';

class _ModuleProgressState extends StatelessWidget {
  final String label;
  final double progress;

  const _ModuleProgressState({required this.label, required this.progress});

  @override
  Widget build(BuildContext context) {
    return NmtkSurfaceCard(
      tone: NmtkTone.info,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 10),
          ZetaProgressBar.standard(progress: progress, isThin: true),
        ],
      ),
    );
  }
}
