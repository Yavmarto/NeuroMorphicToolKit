part of '../environment_editor.dart';

class _ExportDialog extends ConsumerWidget {
  const _ExportDialog({required this.env});
  final EnvironmentInfo env;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exportAsync = ref.watch(environmentExportProvider(env.slug));

    return exportAsync.when(
      loading: () => NmtkContentDialog(
        title: 'Export environment',
        // CEL-421: no fixed 420x420 box — size to the spinner so short phones
        // do not reserve a large empty area above the keyboard.
        content: Padding(
          padding: EdgeInsets.symmetric(
            vertical: context.nmtkTokens.sectionGap * 2,
          ),
          child: const Center(
            child: ZetaProgressCircle(size: ZetaCircleSizes.s),
          ),
        ),
      ),
      error: (e, _) => NmtkContentDialog(
        title: 'Export "${env.displayName}"',
        content: Text(e.toString()),
        actions: [
          ZetaButton.text(
            onPressed: () => Navigator.pop(context),
            label: 'Close',
          ),
          ZetaButton(
            onPressed: () =>
                ref.invalidate(environmentExportProvider(env.slug)),
            label: 'Retry',
          ),
        ],
      ),
      data: (exportState) => _ExportDialogContent(
        env: env,
        exportState: exportState,
        onModeChanged: (mode) =>
            ref.read(environmentExportProvider(env.slug).notifier).reload(mode),
      ),
    );
  }
}
