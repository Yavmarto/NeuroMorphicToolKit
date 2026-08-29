import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/imported_cnl_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/cnl_import_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/import_text_file_picker.dart';

class CnlEditor extends ConsumerStatefulWidget {
  const CnlEditor({super.key, ImportTextFilePicker? filePicker})
    : filePicker = filePicker ?? const _DefaultImportTextFilePicker();

  final ImportTextFilePicker filePicker;

  @override
  ConsumerState<CnlEditor> createState() => _CnlEditorState();
}

class _CnlEditorState extends ConsumerState<CnlEditor> {
  final TextEditingController _controller = TextEditingController();
  bool _isImporting = false;
  String? _importError;

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(specTextProvider);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final importedSpec = ref.watch<ImportedCnlSpec?>(importedCnlSpecProvider);
    final syncIssue = ref.watch<CanvasSyncIssue?>(canvasSyncIssueProvider);

    ref.listen<String>(specTextProvider, (previous, next) {
      if (_controller.text != next) {
        _controller.text = next;
      }
    });

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ZetaButton(
                key: const Key('cnl-import-button'),
                onPressed: _isImporting ? null : _importFile,
                label: _isImporting ? 'Importing…' : 'Import .cnl File',
                leadingIcon: _isImporting ? null : ZetaIcons.upload_file,
              ),
              const SizedBox(width: 8),
              ZetaButton.outline(
                key: const Key('cnl-load-demo-button'),
                onPressed: () =>
                    ref.read(canvasProvider.notifier).loadDemoReflexArc(),
                leadingIcon: Icons
                    .hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                label: 'Load Demo',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  importedSpec?.sourceLabel ??
                      'Edit canonical NeuroCNL directly, or import a `.cnl` file to sync it into the canvas.',
                ),
              ),
            ],
          ),
          if (_importError != null) ...[
            const SizedBox(height: 8),
            Text(
              _importError!,
              style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                color: Zeta.of(context).colors.mainNegative,
              ),
            ),
          ],
          if (syncIssue != null) ...[
            const SizedBox(height: 8),
            Text(
              syncIssue.message,
              style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                color: Zeta.of(context).colors.mainNegative,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: TextField(
              key: const Key('canvas-cnl-editor'),
              controller: _controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                fontFamily: NmtkFontFamilies.monospace,
                package: NmtkFontFamilies.package,
              ),
              onChanged: (value) {
                // Debounced live-typing path — .set() below is reserved for
                // discrete immediate actions (the sync button, file import).
                ref
                    .read<SpecTextController>(specTextProvider.notifier)
                    .update(value);
              },
              decoration: const InputDecoration(
                hintText:
                    'Canonical NeuroCNL appears here. Canvas changes update this text, and syncing this text updates the canvas when the spec stays within the supported canonical subset.',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ZetaButton(
            key: const Key('cnl-sync-button'),
            onPressed: _controller.text.trim().isEmpty
                ? null
                : () {
                    ref
                        .read<SpecTextController>(specTextProvider.notifier)
                        .set(_controller.text);
                  },
            leadingIcon: ZetaIcons.sync,
            label: 'Sync to Canvas',
          ),
        ],
      ),
    );
  }

  Future<void> _importFile() async {
    setState(() {
      _isImporting = true;
      _importError = null;
    });
    try {
      final importedFile = await widget.filePicker.pickFile();
      if (importedFile == null) {
        return;
      }
      final importedSpec = ImportedCnlSpec(
        content: importedFile.text,
        source: ImportedCnlSource.file,
        label: importedFile.name,
      );
      ref.read(importedCnlSpecProvider.notifier).setState(importedSpec);
      unawaited(
        ref
            .read<SpecTextController>(specTextProvider.notifier)
            .set(importedSpec.content),
      );
    } catch (error) {
      setState(() {
        _importError = 'File import failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }
}

class _DefaultImportTextFilePicker extends ImportTextFilePicker {
  const _DefaultImportTextFilePicker();

  @override
  Future<ImportedTextFile?> pickFile({
    List<String> acceptedExtensions = const <String>['cnl'],
  }) {
    return createImportTextFilePicker().pickFile(
      acceptedExtensions: acceptedExtensions,
    );
  }
}
