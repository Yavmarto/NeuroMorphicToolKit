import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/build_timeline.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_assistant_setup_bar.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_agent_notifier.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class StudioAssistantPanel extends ConsumerStatefulWidget {
  const StudioAssistantPanel({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  ConsumerState<StudioAssistantPanel> createState() =>
      _StudioAssistantPanelState();
}

class _StudioAssistantPanelState extends ConsumerState<StudioAssistantPanel> {
  final _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(studioAgentNotifierProvider.notifier);
      unawaited(notifier.ensureSession());
      unawaited(notifier.refreshProviders());
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text;
    if (text.trim().isEmpty) {
      return;
    }
    _messageController.clear();
    await ref.read(studioAgentNotifierProvider.notifier).sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final agentState = ref.watch(studioAgentNotifierProvider);
    final canSend = !agentState.isStreaming && !agentState.isBootstrapping;

    return Material(
      color: colors.surfaceDefault,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Icon(ZetaIcons.chat, color: colors.mainPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Studio assistant',
                      style: Zeta.of(context).textStyles.titleMedium,
                    ),
                  ),
                  if (widget.onClose != null)
                    IconButton(
                      tooltip: 'Close assistant',
                      onPressed: widget.onClose,
                      icon: const Icon(ZetaIcons.close),
                    ),
                ],
              ),
            ),
            const StudioAssistantSetupBar(),
            const Divider(height: 1),
            Expanded(
              child: BuildTimeline(entries: agentState.timeline),
            ),
            if (agentState.errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  agentState.errorMessage!,
                  style: Zeta.of(context).textStyles.bodySmall.copyWith(
                    color: colors.mainNegative,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled: canSend,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Ask the assistant…',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: canSend ? (_) => _sendMessage() : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: canSend ? _sendMessage : null,
                    child: agentState.isStreaming
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(ZetaIcons.send, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
