import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:neuro_toolkit/ui_core/zeta_theme.dart';

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
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Raw SSH output copied'),
        showCloseIcon: true,
      ),
    );
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
    final media = MediaQuery.sizeOf(context);
    final width = media.width < 720 ? media.width - 32 : 680.0;
    final height = (media.height * 0.72).clamp(320.0, 720.0);
    final output = widget.lines.isEmpty
        ? widget.emptyMessage
        : widget.lines.join('\n');
    return AlertDialog(
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
        child: SizedBox(
          width: width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLowest,
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              key: const Key('nmtk-log-viewer-scroll'),
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
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
        ZetaButton.outline(
          key: const Key('nmtk-log-viewer-copy'),
          onPressed: widget.lines.isEmpty ? null : _copyOutput,
          label: 'Copy output',
        ),
        ZetaButton(
          key: const Key('nmtk-log-viewer-close'),
          onPressed: () => Navigator.of(context).pop(),
          label: 'Close',
        ),
      ],
    );
  }
}
