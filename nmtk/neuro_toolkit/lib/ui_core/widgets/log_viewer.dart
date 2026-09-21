import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// State-management-independent live command transcript dialog.
///
/// The viewer follows new output while the reader remains at the bottom. If
/// they scroll upward, their position is preserved until they return there.
class NmtkLogViewerDialog extends StatefulWidget {
  const NmtkLogViewerDialog({
    super.key,
    required this.title,
    required this.lines,
    required this.isRunning,
    this.emptyMessage = 'Waiting for server output…',
  });

  final String title;
  final List<String> lines;
  final bool isRunning;
  final String emptyMessage;

  @override
  State<NmtkLogViewerDialog> createState() => _NmtkLogViewerDialogState();
}

class _NmtkLogViewerDialogState extends State<NmtkLogViewerDialog> {
  final ScrollController _scrollController = ScrollController();
  bool _shouldFollow = true;

  static const double _minTapTarget = 44;
  static const double _titleActionsReserve = 120;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_trackFollowState);
  }

  @override
  void didUpdateWidget(covariant NmtkLogViewerDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_shouldFollow && oldWidget.lines.length != widget.lines.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  void _trackFollowState() {
    if (!_scrollController.hasClients) return;
    final remaining =
        _scrollController.position.maxScrollExtent - _scrollController.offset;
    _shouldFollow = remaining < 32;
  }

  void _scrollToEnd() {
    if (!mounted || !_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: widget.lines.join('\n')));
    if (!mounted) return;
    NmtkSnackBars.success(context, 'Raw SSH output copied');
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_trackFollowState)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tokens = NmtkShellTokens.of(context);
    final media = MediaQuery.of(context);
    final viewInsets = media.viewInsets;
    final margin = tokens.sectionGap;
    final isCompact = media.size.width < NmtkShellTokens.compactBreakpoint;
    final dialogWidth = isCompact
        ? media.size.width - margin * 2
        : 680.0.clamp(0.0, media.size.width - margin * 2);
    final availableHeight =
        media.size.height - viewInsets.vertical - margin * 2;
    final contentMaxHeight = (availableHeight - _titleActionsReserve).clamp(
      160.0,
      720.0,
    );
    final output = widget.lines.isEmpty
        ? widget.emptyMessage
        : widget.lines.join('\n');

    return AlertDialog(
      insetPadding: EdgeInsets.fromLTRB(
        margin,
        margin + viewInsets.top,
        margin,
        margin + viewInsets.bottom,
      ),
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
          if (widget.isRunning)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      content: Semantics(
        label: 'Live sanitized raw SSH output',
        liveRegion: widget.isRunning,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogWidth,
            maxHeight: contentMaxHeight,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLowest,
              border: Border.all(color: colors.outlineVariant),
              borderRadius: NmtkDesignTokens.smallShape,
            ),
            child: SingleChildScrollView(
              key: const Key('nmtk-log-viewer-scroll'),
              controller: _scrollController,
              padding: EdgeInsets.all(tokens.sectionGap),
              child: SelectableText(
                output,
                key: const Key('nmtk-log-viewer-output'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'JetBrains Mono',
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minTapTarget),
          child: ZetaButton.outline(
            key: const Key('nmtk-log-viewer-copy'),
            onPressed: widget.lines.isEmpty ? null : _copyOutput,
            label: 'Copy output',
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minTapTarget),
          child: ZetaButton(
            key: const Key('nmtk-log-viewer-close'),
            onPressed: () => Navigator.of(context).pop(),
            label: 'Close',
          ),
        ),
      ],
    );
  }
}
