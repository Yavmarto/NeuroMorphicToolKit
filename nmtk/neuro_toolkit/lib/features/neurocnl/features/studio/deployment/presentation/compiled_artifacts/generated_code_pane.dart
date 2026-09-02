import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';

/// Available generated-code views.
enum _GeneratedCodeKind { cnl, nir }

/// Code viewer and artifact download controls for a generated model.

class GeneratedCodePane extends StatefulWidget {
  const GeneratedCodePane({
    super.key,
    required this.cnlDocument,
    required this.nirCode,
    required this.onDownloadNir,
  });

  final String? cnlDocument;
  final String? nirCode;
  final Future<void> Function()? onDownloadNir;

  @override
  State<GeneratedCodePane> createState() => _GeneratedCodePaneState();
}

class _GeneratedCodePaneState extends State<GeneratedCodePane> {
  bool _copied = false;
  _GeneratedCodeKind _selectedKind = _GeneratedCodeKind.cnl;

  String? get _activeCode {
    switch (_selectedKind) {
      case _GeneratedCodeKind.cnl:
        return widget.cnlDocument;
      case _GeneratedCodeKind.nir:
        return widget.nirCode;
    }
  }

  String get _activeFilename {
    switch (_selectedKind) {
      case _GeneratedCodeKind.cnl:
        return 'roundtrip.cnl';
      case _GeneratedCodeKind.nir:
        // This is a JSON inspection preview, not the binary .nir artifact.
        // The actual binary is downloaded via the Download button.
        return 'graph-preview.json';
    }
  }

  String get _emptyStateLabel {
    switch (_selectedKind) {
      case _GeneratedCodeKind.cnl:
        return 'Run the model to see\nround-trip CNL output.';
      case _GeneratedCodeKind.nir:
        return 'Run the model to see\nNIR graph preview.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _activeCode;
    final actionRowChildren = <Widget>[
      SegmentedButton<_GeneratedCodeKind>(
        segments: const [
          ButtonSegment<_GeneratedCodeKind>(
            value: _GeneratedCodeKind.cnl,
            label: Text('CNL'),
          ),
          ButtonSegment<_GeneratedCodeKind>(
            value: _GeneratedCodeKind.nir,
            // Labelled as 'NIR preview' to clarify this is JSON inspection,
            // not the binary .nir artifact.
            label: Text('NIR preview'),
          ),
        ],
        selected: {_selectedKind},
        onSelectionChanged: (selection) {
          setState(() {
            _selectedKind = selection.first;
            _copied = false;
          });
        },
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStateProperty.all(
            Zeta.of(context).textStyles.labelSmall.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ];
    if (code != null) {
      if (_selectedKind == _GeneratedCodeKind.cnl) {
        // CNL tab: copy to clipboard is useful (it's valid CNL text).
        actionRowChildren.add(
          GestureDetector(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: code));
              setState(() => _copied = true);
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => _copied = false);
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _copied
                    ? AppTheme.success.withValues(alpha: 0.12)
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(
                  NmtkShellTokens.of(context).radiusSm,
                ),
                border: Border.all(
                  color: _copied
                      ? AppTheme.success.withValues(alpha: 0.5)
                      : AppTheme.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _copied
                        ? ZetaIcons.check_circle
                        : Icons
                              .copy_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                    size: 12,
                    color: _copied ? AppTheme.success : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _copied ? 'Copied' : 'Copy',
                    style: Zeta.of(context).textStyles.labelSmall.copyWith(
                      color: _copied
                          ? AppTheme.success
                          : AppTheme.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        // NIR preview tab: this is JSON for inspection only, not a valid .nir
        // binary file. Show a Download button that fetches the real binary
        // artifact from POST /api/export instead.
        if (widget.onDownloadNir != null) {
          actionRowChildren.add(
            GestureDetector(
              onTap: widget.onDownloadNir,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryDim.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(
                    NmtkShellTokens.of(context).radiusSm,
                  ),
                  border: Border.all(
                    color: AppTheme.primaryDim.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(ZetaIcons.download, size: 12, color: AppTheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Download .nir',
                      style: Zeta.of(context).textStyles.labelSmall.copyWith(
                        color: AppTheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compactHeader = constraints.maxWidth < 360;
                if (compactHeader) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons
                                .code, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                            size: 14,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _activeFilename,
                            style: Zeta.of(context).textStyles.labelSmall.copyWith(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: actionRowChildren,
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    const Icon(
                      Icons.code, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                      size: 14,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _activeFilename,
                      style: Zeta.of(context).textStyles.labelSmall.copyWith(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          alignment: WrapAlignment.end,
                          children: actionRowChildren,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const Divider(color: AppTheme.border, height: 1),
          Expanded(
            child: code == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons
                              .code_off_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                          size: 32,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _emptyStateLabel,
                          textAlign: TextAlign.center,
                          style: Zeta.of(context).textStyles.bodyXSmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      code,
                      // ZETA-MIGRATION-EXEMPT: generated code is monospace (JetBrains
                      // Mono) — Zeta (IBM Plex Sans) has no monospace text style.
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 11,
                        height: 1.5,
                        fontFamily: AppTheme.monospaceFontFamily,
                        package: AppTheme.fontPackage,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
