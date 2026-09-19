part of '../environment_editor.dart';

class _ExportDialogContent extends StatelessWidget {
  const _ExportDialogContent({
    required this.env,
    required this.exportState,
    required this.onModeChanged,
  });

  final EnvironmentInfo env;
  final EnvironmentExportState exportState;
  final ValueChanged<String> onModeChanged;

  Future<void> _save(BuildContext context) async {
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: exportState.body));
      if (!context.mounted) return;
      NmtkToasts.success(
        context,
        'Copied to clipboard (file save unsupported on web).',
      );
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${env.slug}-requirements.txt');
      await file.writeAsString(exportState.body);
      if (!context.mounted) return;
      NmtkToasts.success(context, 'Saved to ${file.path}');
    } catch (e) {
      if (!context.mounted) return;
      NmtkToasts.error(context, 'Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // CEL-421: replace the fixed 420 px body with a viewport-relative cap so
    // the code pane never forces clipping on an iPhone SE-class screen.
    final bodyHeight = (MediaQuery.sizeOf(context).height * 0.5).clamp(
      200.0,
      420.0,
    );
    return NmtkContentDialog(
      title: 'Export "${env.displayName}"',
      content: SizedBox(
        width: double.maxFinite,
        height: bodyHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Contents',
                  style: Zeta.of(context).textStyles.labelMedium,
                ),
                const Spacer(),
                if (!env.immutable)
                  Flexible(
                    // CEL-421: Flexible so the 220 px select shrinks instead
                    // of overflowing the near-full-width mobile dialog.
                    child: SizedBox(
                      width: 220,
                      child: ZetaSelectInput<String>(
                        initialValue: exportState.mode,
                        disabled: exportState.loading,
                        dropdownSemantics: 'Choose export contents',
                        onChange: (value) {
                          if (value != null) onModeChanged(value);
                        },
                        items: [
                          ZetaDropdownItem(
                            value: 'delta',
                            label: 'Added packages only',
                          ),
                          ZetaDropdownItem(
                            value: 'full',
                            label: 'Full environment',
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: context.nmtkTokens.compactGap),
            Expanded(
              child: exportState.loading
                  ? const Center(
                      child: ZetaProgressCircle(size: ZetaCircleSizes.s),
                    )
                  : exportState.error != null
                  ? Text(exportState.error!)
                  : Scrollbar(
                      child: SingleChildScrollView(
                        child: SelectableText(
                          exportState.body.isEmpty
                              ? '(no packages)'
                              : exportState.body,
                          style: Zeta.of(context).textStyles.bodySmall.copyWith(
                            fontFamily: NmtkFontFamilies.monospace,
                            package: NmtkFontFamilies.package,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        ZetaButton.text(
          onPressed: () => Navigator.pop(context),
          label: 'Close',
        ),
        ZetaButton.outline(
          onPressed: exportState.body.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(
                    ClipboardData(text: exportState.body),
                  );
                  if (!context.mounted) return;
                  NmtkToasts.success(context, 'Copied to clipboard');
                },
          label: 'Copy',
        ),
        ZetaButton(
          onPressed: exportState.body.isEmpty ? null : () => _save(context),
          label: 'Save file',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _ImportDialog — paste a requirements.txt + name to create a new environment.
// ---------------------------------------------------------------------------
