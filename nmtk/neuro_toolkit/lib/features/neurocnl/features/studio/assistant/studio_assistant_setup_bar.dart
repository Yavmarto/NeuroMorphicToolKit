import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_agent_models.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_agent_notifier.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class StudioAssistantSetupBar extends ConsumerStatefulWidget {
  const StudioAssistantSetupBar({super.key});

  @override
  ConsumerState<StudioAssistantSetupBar> createState() =>
      _StudioAssistantSetupBarState();
}

class _StudioAssistantSetupBarState extends ConsumerState<StudioAssistantSetupBar> {
  final _modelController = TextEditingController();
  final _repoRootController = TextEditingController();
  String? _selectedProviderId;
  ProviderSubscription<StudioAgentState>? _agentStateSub;

  @override
  void initState() {
    super.initState();
    _agentStateSub = ref.listenManual(
      studioAgentNotifierProvider,
      (previous, next) {
        final snapshotChanged =
            previous?.providersSnapshot != next.providersSnapshot;
        final repoRootChanged = previous?.mcpRepoRoot != next.mcpRepoRoot;
        if (!snapshotChanged && !repoRootChanged) {
          return;
        }
        setState(() => _syncFromState(next));
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _agentStateSub?.close();
    _modelController.dispose();
    _repoRootController.dispose();
    super.dispose();
  }

  void _syncFromState(StudioAgentState agentState) {
    final snapshot = agentState.providersSnapshot;
    _syncFromSnapshot(snapshot);
    final repoRoot = agentState.mcpRepoRoot;
    if (repoRoot != null && _repoRootController.text != repoRoot) {
      _repoRootController.text = repoRoot;
    }
  }

  void _syncFromSnapshot(StudioAgentProvidersSnapshot? snapshot) {
    if (snapshot == null) {
      return;
    }
    _selectedProviderId = snapshot.activeProviderId;
    final model = snapshot.activeModel;
    if (model != null && _modelController.text != model) {
      _modelController.text = model;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final textStyle = Zeta.of(context).textStyles.bodySmall;
    final agentState = ref.watch(studioAgentNotifierProvider);
    final snapshot = agentState.providersSnapshot;

    final providers = snapshot?.providers ?? const <StudioLlmProviderInfo>[];
    final availableProviders =
        providers.where((provider) => provider.available).toList();
    final activeProvider = _findProvider(
      providers,
      snapshot?.activeProviderId,
    );
    final hasActiveProvider = activeProvider?.available ?? false;
    final selectedSupportsMcp = activeProvider?.supportsMcpInstall ?? false;
    final mcpInstalled = activeProvider?.mcpInstalled ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                snapshot?.mcpToolsReady ?? false
                    ? ZetaIcons.check_circle
                    : ZetaIcons.warning_outline,
                size: 16,
                color: snapshot?.mcpToolsReady ?? false
                    ? colors.mainPositive
                    : colors.mainWarning,
              ),
              Text(
                snapshot?.mcpToolsReady ?? false
                    ? 'Build tools ready (${snapshot?.mcpToolCount ?? 0} MCP tools via backend)'
                    : 'Build tools unavailable',
                style: textStyle,
              ),
            ],
          ),
          if (snapshot?.probeHostNote != null) ...[
            const SizedBox(height: 4),
            Text(snapshot!.probeHostNote!, style: textStyle),
          ],
          const SizedBox(height: 8),
          if (agentState.isLoadingProviders && providers.isEmpty)
            const LinearProgressIndicator(minHeight: 2)
          else ...[
            DropdownButtonFormField<String>(
              value: _selectedProviderId,
              decoration: const InputDecoration(
                labelText: 'LLM provider',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              hint: Text(
                availableProviders.isEmpty
                    ? 'No local LLM found'
                    : 'Auto-detect',
              ),
              items: [
                for (final provider in providers)
                  DropdownMenuItem<String>(
                    value: provider.providerId,
                    enabled: provider.available,
                    child: Text(
                      provider.available
                          ? provider.label
                          : '${provider.label} (not installed)',
                    ),
                  ),
              ],
              onChanged: agentState.isStreaming
                  ? null
                  : (value) async {
                      setState(() => _selectedProviderId = value);
                      await ref
                          .read(studioAgentNotifierProvider.notifier)
                          .setActiveProvider(providerId: value);
                    },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _modelController,
                    enabled: !agentState.isStreaming,
                    decoration: const InputDecoration(
                      labelText: 'Model name',
                      hintText: 'e.g. llama3.2',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: agentState.isStreaming
                        ? null
                        : (value) {
                            unawaited(
                              ref
                                  .read(studioAgentNotifierProvider.notifier)
                                  .setActiveProvider(
                                    providerId: _selectedProviderId,
                                    model: value.trim(),
                                  ),
                            );
                          },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: agentState.isStreaming
                      ? null
                      : () {
                          unawaited(
                            ref
                                .read(studioAgentNotifierProvider.notifier)
                                .setActiveProvider(
                                  providerId: _selectedProviderId,
                                  model: _modelController.text.trim(),
                                ),
                          );
                        },
                  child: const Text('Apply'),
                ),
              ],
            ),
            if (selectedSupportsMcp && hasActiveProvider) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _repoRootController,
                enabled: !agentState.isStreaming && !agentState.isInstallingMcp,
                decoration: const InputDecoration(
                  labelText: 'NeuroMorphicToolKit repo path (for MCP)',
                  hintText: '~/NeuroMorphicToolKit',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) {
                  unawaited(
                    ref
                        .read(studioAgentNotifierProvider.notifier)
                        .saveMcpRepoRoot(value),
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      mcpInstalled
                          ? 'External MCP: installed for ${activeProvider!.label}'
                          : 'External MCP: not installed for ${activeProvider!.label}',
                      style: textStyle.copyWith(
                        color: mcpInstalled
                            ? colors.mainPositive
                            : colors.mainWarning,
                      ),
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed:
                        agentState.isStreaming || agentState.isInstallingMcp
                        ? null
                        : () async {
                            final repoRoot = _repoRootController.text.trim();
                            if (repoRoot.isNotEmpty) {
                              await ref
                                  .read(studioAgentNotifierProvider.notifier)
                                  .saveMcpRepoRoot(repoRoot);
                            }
                            await ref
                                .read(studioAgentNotifierProvider.notifier)
                                .installMcpForProvider(
                                  activeProvider.providerId,
                                );
                          },
                    child: Text(mcpInstalled ? 'Reinstall MCP' : 'Install MCP'),
                  ),
                ],
              ),
              if (activeProvider.mcpConfigHint != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Config: ${activeProvider.mcpConfigHint}',
                    style: textStyle,
                  ),
                ),
            ],
            if (agentState.mcpStatusMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SelectableText(
                  agentState.mcpStatusMessage!,
                  style: textStyle,
                ),
              ),
            if (snapshot?.probeHostNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  snapshot!.probeHostNote!,
                  style: textStyle,
                ),
              ),
            if (!hasActiveProvider && providers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Install Ollama, LM Studio, or a CLI harness on the connected backend server, then refresh.',
                  style: textStyle.copyWith(color: colors.mainWarning),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

StudioLlmProviderInfo? _findProvider(
  List<StudioLlmProviderInfo> providers,
  String? providerId,
) {
  if (providerId == null) {
    return null;
  }
  for (final provider in providers) {
    if (provider.providerId == providerId) {
      return provider;
    }
  }
  return null;
}
