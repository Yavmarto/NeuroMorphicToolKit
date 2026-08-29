import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/canvas/pipeline_cnl_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';

/// Read-mostly CNL preview/edit panel for the Pipeline tab.
///
/// Displays [PipelineCnlController]'s debounced rendering of the current
/// pipeline config as Train/Evaluate/Export CNL text. Hand-edits are
/// staged locally in this widget's [TextEditingController] and only
/// applied back onto the pipeline config via the explicit "Apply CNL"
/// button — mirrors the Architecture tab's `CnlEditor` explicit-sync
/// button, but one-directional by default since
/// `/notebook/parse-pipeline-cnl` is fail-closed (no live "preview as
/// you type" parsing).
class PipelineCnlPanel extends ConsumerStatefulWidget {
  const PipelineCnlPanel({super.key});

  @override
  ConsumerState<PipelineCnlPanel> createState() => _PipelineCnlPanelState();
}

class _PipelineCnlPanelState extends ConsumerState<PipelineCnlPanel> {
  final TextEditingController _controller = TextEditingController();
  bool _isApplying = false;
  String? _applyError;
  String _lastRenderedText = '';

  @override
  void initState() {
    super.initState();
    final current = ref.read(pipelineCnlProvider).value;
    if (current != null) {
      _controller.text = current;
      _lastRenderedText = current;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cnlAsync = ref.watch(pipelineCnlProvider);
    final textStyles = Zeta.of(context).textStyles;

    ref.listen<AsyncValue<String>>(pipelineCnlProvider, (previous, next) {
      final text = next.value;
      if (text == null || text == _lastRenderedText) return;
      final hadUnappliedEdits = _controller.text != _lastRenderedText;
      _lastRenderedText = text;
      if (!hadUnappliedEdits) {
        _controller.text = text;
      }
    });

    final hasUnappliedEdits = _controller.text != _lastRenderedText;

    // Allowed: single-topic surface
    return NmtkSurfaceCard(
      title: 'CNL Preview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Train/Evaluate/Export sentences derived from this pipeline's "
            'configuration. Some fields (dataset, framework, advanced '
            "surrogate/nengo settings) aren't represented here — edit "
            'those via the form controls above.',
            style: textStyles.bodySmall,
          ),
          const SizedBox(height: 12),
          if (cnlAsync.isLoading && _controller.text.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            TextField(
              key: const Key('pipeline-cnl-text-field'),
              controller: _controller,
              maxLines: 6,
              minLines: 3,
              style: textStyles.bodyMedium.copyWith(
                fontFamily: NmtkFontFamilies.monospace,
                package: NmtkFontFamilies.package,
              ),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(12),
              ),
              onChanged: (_) => setState(() {}),
            ),
          if (_applyError != null) ...[
            const SizedBox(height: 8),
            Text(
              _applyError!,
              key: const Key('pipeline-cnl-apply-error'),
              style: textStyles.bodySmall.copyWith(
                color: Zeta.of(context).colors.mainNegative,
              ),
            ),
          ] else if (cnlAsync.hasError) ...[
            const SizedBox(height: 8),
            Text(
              'Failed to render CNL preview: ${cnlAsync.error}',
              style: textStyles.bodySmall.copyWith(
                color: Zeta.of(context).colors.mainNegative,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ZetaButton(
            key: const Key('pipeline-cnl-apply-button'),
            onPressed: (!hasUnappliedEdits || _isApplying)
                ? null
                : _applyCnlText,
            label: _isApplying ? 'Applying…' : 'Apply CNL',
            leadingIcon: _isApplying ? null : ZetaIcons.sync,
          ),
        ],
      ),
    );
  }

  Future<void> _applyCnlText() async {
    setState(() {
      _isApplying = true;
      _applyError = null;
    });
    try {
      await ref
          .read(pipelineCnlProvider.notifier)
          .applyCnlText(_controller.text);
      _lastRenderedText = _controller.text;
    } catch (e) {
      setState(() {
        _applyError = e is ApiException
            ? 'CNL parse failed (${e.statusCode}): ${e.body}'
            : 'CNL parse failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isApplying = false;
        });
      }
    }
  }
}
