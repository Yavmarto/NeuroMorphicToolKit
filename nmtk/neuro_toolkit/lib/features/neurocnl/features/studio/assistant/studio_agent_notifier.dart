import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_agent_models.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_agent_service.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_local_harness.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_mcp_installer.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/feature_launch_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/step_unlock_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/admin_token_http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudioAgentState {
  const StudioAgentState({
    this.sessionId,
    this.isBootstrapping = false,
    this.isStreaming = false,
    this.isLoadingProviders = false,
    this.errorMessage,
    this.timeline = const [],
    this.pendingStepSuggestions = const [],
    this.providersSnapshot,
    this.mcpRepoRoot,
    this.mcpStatusMessage,
    this.isInstallingMcp = false,
  });

  final String? sessionId;
  final bool isBootstrapping;
  final bool isStreaming;
  final bool isLoadingProviders;
  final String? errorMessage;
  final List<StudioAgentTimelineEntry> timeline;
  final List<StudioAgentStepSuggestion> pendingStepSuggestions;
  final StudioAgentProvidersSnapshot? providersSnapshot;
  final String? mcpRepoRoot;
  final String? mcpStatusMessage;
  final bool isInstallingMcp;

  StudioAgentState copyWith({
    String? sessionId,
    bool? isBootstrapping,
    bool? isStreaming,
    bool? isLoadingProviders,
    String? errorMessage,
    bool clearError = false,
    List<StudioAgentTimelineEntry>? timeline,
    List<StudioAgentStepSuggestion>? pendingStepSuggestions,
    StudioAgentProvidersSnapshot? providersSnapshot,
    String? mcpRepoRoot,
    String? mcpStatusMessage,
    bool? isInstallingMcp,
    bool clearMcpStatus = false,
  }) {
    return StudioAgentState(
      sessionId: sessionId ?? this.sessionId,
      isBootstrapping: isBootstrapping ?? this.isBootstrapping,
      isStreaming: isStreaming ?? this.isStreaming,
      isLoadingProviders: isLoadingProviders ?? this.isLoadingProviders,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      timeline: timeline ?? this.timeline,
      pendingStepSuggestions:
          pendingStepSuggestions ?? this.pendingStepSuggestions,
      providersSnapshot: providersSnapshot ?? this.providersSnapshot,
      mcpRepoRoot: mcpRepoRoot ?? this.mcpRepoRoot,
      mcpStatusMessage: clearMcpStatus
          ? null
          : mcpStatusMessage ?? this.mcpStatusMessage,
      isInstallingMcp: isInstallingMcp ?? this.isInstallingMcp,
    );
  }
}

class StudioAgentStepSuggestion {
  const StudioAgentStepSuggestion({
    required this.step,
    this.label,
    this.reason,
  });

  final String step;
  final String? label;
  final String? reason;
}

final studioAgentServiceProvider = Provider<StudioAgentService>((ref) {
  final launchContext = ref.watch(featureLaunchContextProvider);
  final baseUrl = launchContext.backendUri
      .replace(path: '/api/studio/agent')
      .toString();
  final client = AdminTokenHttpClient(
    adminToken: launchContext.authentication.adminToken,
    onReportError: launchContext.onReportError,
    onRecovered: launchContext.onRecovered,
  );
  ref.onDispose(client.close);
  return StudioAgentService(baseUrl: baseUrl, httpClient: client);
});

class StudioAgentNotifier extends Notifier<StudioAgentState> {
  static const _mcpRepoRootKey = 'studio_mcp_repo_root';

  int _entryCounter = 0;
  StreamSubscription<StudioAgentStreamEvent>? _chatSubscription;

  @override
  StudioAgentState build() {
    ref.onDispose(() {
      unawaited(_chatSubscription?.cancel());
    });
    unawaited(_loadMcpRepoRoot());
    return const StudioAgentState();
  }

  Future<void> _loadMcpRepoRoot() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_mcpRepoRootKey)?.trim();
    if (saved != null && saved.isNotEmpty) {
      state = state.copyWith(mcpRepoRoot: saved);
    }
  }

  Future<void> saveMcpRepoRoot(String repoRoot) async {
    final trimmed = repoRoot.trim();
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await prefs.remove(_mcpRepoRootKey);
      state = state.copyWith(mcpRepoRoot: '');
      return;
    }
    await prefs.setString(_mcpRepoRootKey, trimmed);
    state = state.copyWith(mcpRepoRoot: trimmed, clearMcpStatus: true);
  }

  StudioAgentProvidersSnapshot _enrichProviderSnapshot(
    StudioAgentProvidersSnapshot snapshot,
  ) {
    return _attachMcpInstallStatus(
      StudioLocalHarness.mergeDesktopProbes(snapshot),
    );
  }

  StudioAgentProvidersSnapshot _attachMcpInstallStatus(
    StudioAgentProvidersSnapshot snapshot,
  ) {
    if (!StudioMcpInstaller.isSupported) {
      return snapshot;
    }
    final installer = StudioMcpInstaller();
    final providers = snapshot.providers
        .map(
          (provider) => provider.supportsMcpInstall
              ? provider.copyWith(
                  mcpInstalled: installer.isInstalled(provider.providerId),
                )
              : provider,
        )
        .toList(growable: false);
    return snapshot.copyWithProviders(providers);
  }

  /// ponytail: picks first PATH-resolved CLI harness; upgrade path is user preference store.
  Future<StudioAgentProvidersSnapshot> _autoSelectDesktopHarness(
    StudioAgentProvidersSnapshot snapshot,
  ) async {
    if (!StudioLocalHarness.isSupported || snapshot.activeProviderId != null) {
      return snapshot;
    }
    final providerId = StudioLocalHarness.firstAvailableCliProviderId(
      snapshot.providers,
    );
    if (providerId == null) {
      return snapshot;
    }
    return _enrichProviderSnapshot(
      await ref
          .read(studioAgentServiceProvider)
          .updateActiveProvider(providerId: providerId),
    );
  }

  String _nextEntryId() {
    _entryCounter += 1;
    return 'entry-$_entryCounter';
  }

  Future<void> ensureSession({String? workspaceId}) async {
    if (state.sessionId != null || state.isBootstrapping) {
      return;
    }
    state = state.copyWith(isBootstrapping: true, clearError: true);
    try {
      final sessionId = await ref
          .read(studioAgentServiceProvider)
          .createSession(workspaceId: workspaceId);
      state = state.copyWith(
        sessionId: sessionId,
        isBootstrapping: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isBootstrapping: false,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> refreshProviders() async {
    if (state.isLoadingProviders) {
      return;
    }
    state = state.copyWith(isLoadingProviders: true, clearError: true);
    try {
      var snapshot = _enrichProviderSnapshot(
        await ref.read(studioAgentServiceProvider).fetchProviders(),
      );
      snapshot = await _autoSelectDesktopHarness(snapshot);
      state = state.copyWith(
        providersSnapshot: snapshot,
        isLoadingProviders: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isLoadingProviders: false,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> setActiveProvider({
    required String? providerId,
    String? model,
  }) async {
    state = state.copyWith(isLoadingProviders: true, clearError: true);
    try {
      final snapshot = _enrichProviderSnapshot(
        await ref
            .read(studioAgentServiceProvider)
            .updateActiveProvider(providerId: providerId, model: model),
      );
      state = state.copyWith(
        providersSnapshot: snapshot,
        isLoadingProviders: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isLoadingProviders: false,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> installMcpForProvider(String providerId) async {
    if (!StudioMcpInstaller.isSupported) {
      state = state.copyWith(
        mcpStatusMessage: 'MCP install is available on desktop only.',
      );
      return;
    }
    state = state.copyWith(isInstallingMcp: true, clearMcpStatus: true);
    try {
      final repoRoot = (state.mcpRepoRoot ?? '').trim().isEmpty
          ? null
          : state.mcpRepoRoot!.trim();
      final serverEntry = await ref
          .read(studioAgentServiceProvider)
          .fetchMcpServerEntry(repoRoot: repoRoot);
      if (serverEntry['requires_repo_root'] == true && repoRoot == null) {
        state = state.copyWith(
          isInstallingMcp: false,
          mcpStatusMessage:
              'Set the NeuroMorphicToolKit repo path below, then install MCP again.',
        );
        return;
      }
      final installer = StudioMcpInstaller();
      if (!installer.canAutoInstall(providerId)) {
        final snippet = installer.snippetForProvider(serverEntry);
        var message =
            'Copy this into your ${installer.providerLabel(providerId)} MCP config:\n$snippet';
        if (providerId == 'antigravity') {
          final instructions = await ref
              .read(studioAgentServiceProvider)
              .fetchInstructionsMarkdown();
          final skillResult = installer.installSkill(
            providerId: providerId,
            markdown: instructions,
          );
          if (skillResult.success) {
            message =
                '${skillResult.message}\n\nAlso add this MCP server (agy /mcp or settings.json):\n$snippet';
          }
        }
        state = state.copyWith(
          isInstallingMcp: false,
          mcpStatusMessage: message,
        );
        return;
      }
      final result = installer.install(
        providerId: providerId,
        serverEntry: serverEntry,
      );
      final snapshot = state.providersSnapshot == null
          ? null
          : _attachMcpInstallStatus(state.providersSnapshot!);
      state = state.copyWith(
        isInstallingMcp: false,
        providersSnapshot: snapshot,
        mcpStatusMessage: result.message,
      );
    } catch (error) {
      state = state.copyWith(
        isInstallingMcp: false,
        mcpStatusMessage: error.toString(),
      );
    }
  }

  Future<void> sendMessage(
    String message, {
    List<StudioToolCallRequest> toolCalls = const [],
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty && toolCalls.isEmpty) {
      return;
    }
    if (state.isStreaming) {
      return;
    }

    await ensureSession(workspaceId: ref.read(workspaceProvider).workspaceName);
    final sessionId = state.sessionId;
    if (sessionId == null) {
      return;
    }

    final timeline = List<StudioAgentTimelineEntry>.from(state.timeline);
    if (trimmed.isNotEmpty) {
      timeline.add(
        StudioAgentTimelineEntry(
          id: _nextEntryId(),
          kind: StudioAgentTimelineKind.userMessage,
          text: trimmed,
        ),
      );
    }

    state = state.copyWith(
      timeline: timeline,
      isStreaming: true,
      clearError: true,
      pendingStepSuggestions: const [],
    );

    final service = ref.read(studioAgentServiceProvider);
    if (state.providersSnapshot != null &&
        state.providersSnapshot!.activeProviderId == null) {
      final snapshot = await _autoSelectDesktopHarness(
        state.providersSnapshot!,
      );
      state = state.copyWith(providersSnapshot: snapshot);
    }
    var resolvedToolCalls = toolCalls;
    String? assistantContent;
    final activeProviderId = state.providersSnapshot?.activeProviderId;
    if (trimmed.isNotEmpty &&
        toolCalls.isEmpty &&
        StudioLocalHarness.isCliProvider(activeProviderId)) {
      try {
        final session = await service.fetchSession(sessionId);
        final rawMessages = session['messages'] as List<dynamic>? ?? const [];
        final messages = rawMessages.whereType<Map<String, dynamic>>().toList(
          growable: false,
        );
        final instructions = await service.fetchInstructionsMarkdown();
        final localResult = await StudioLocalHarness.maybeRun(
          providerId: activeProviderId!,
          messages: messages,
          instructionsMarkdown: instructions,
          model: state.providersSnapshot?.activeModel,
        );
        if (localResult != null) {
          assistantContent = localResult.content;
          resolvedToolCalls = localResult.toolCalls;
        }
      } on StudioLocalHarnessException catch (error) {
        state = state.copyWith(isStreaming: false, errorMessage: error.message);
        return;
      }
    }

    await _chatSubscription?.cancel();
    _chatSubscription = service
        .chat(
          sessionId: sessionId,
          message: trimmed.isEmpty ? null : trimmed,
          toolCalls: resolvedToolCalls,
          assistantContent: assistantContent,
        )
        .listen(
          _onStreamEvent,
          onError: (Object error) {
            state = state.copyWith(
              isStreaming: false,
              errorMessage: error.toString(),
            );
          },
          onDone: () {
            if (state.isStreaming) {
              state = state.copyWith(isStreaming: false);
            }
          },
        );
  }

  void _onStreamEvent(StudioAgentStreamEvent event) {
    switch (event) {
      case StudioAgentAssistantDelta(:final text):
        if (text.isEmpty) {
          return;
        }
        final timeline = List<StudioAgentTimelineEntry>.from(state.timeline);
        final last = timeline.isNotEmpty ? timeline.last : null;
        if (last?.kind == StudioAgentTimelineKind.assistantText) {
          timeline[timeline.length - 1] = StudioAgentTimelineEntry(
            id: last!.id,
            kind: StudioAgentTimelineKind.assistantText,
            text: '${last.text ?? ''}$text',
          );
        } else {
          timeline.add(
            StudioAgentTimelineEntry(
              id: _nextEntryId(),
              kind: StudioAgentTimelineKind.assistantText,
              text: text,
            ),
          );
        }
        state = state.copyWith(timeline: timeline);
      case StudioAgentToolStarted(:final tool, :final arguments):
        final timeline = List<StudioAgentTimelineEntry>.from(state.timeline)
          ..add(
            StudioAgentTimelineEntry(
              id: _nextEntryId(),
              kind: StudioAgentTimelineKind.toolCall,
              toolName: tool,
              toolStatus: StudioAgentToolStatus.running,
              toolArguments: arguments,
            ),
          );
        state = state.copyWith(timeline: timeline);
      case StudioAgentToolFinished(:final tool, :final result):
        final timeline = List<StudioAgentTimelineEntry>.from(state.timeline);
        final index = timeline.lastIndexWhere(
          (entry) =>
              entry.kind == StudioAgentTimelineKind.toolCall &&
              entry.toolName == tool &&
              entry.toolStatus == StudioAgentToolStatus.running,
        );
        if (index >= 0) {
          timeline[index] = timeline[index].copyWith(
            toolStatus: result.status == 'error'
                ? StudioAgentToolStatus.failed
                : StudioAgentToolStatus.succeeded,
            toolResult: result,
          );
        } else {
          timeline.add(
            StudioAgentTimelineEntry(
              id: _nextEntryId(),
              kind: StudioAgentTimelineKind.toolCall,
              toolName: tool,
              toolStatus: result.status == 'error'
                  ? StudioAgentToolStatus.failed
                  : StudioAgentToolStatus.succeeded,
              toolResult: result,
            ),
          );
        }
        state = state.copyWith(timeline: timeline);
      case StudioAgentStepSuggested(:final step, :final reason, :final label):
        if (step.isEmpty) {
          return;
        }
        final timeline = List<StudioAgentTimelineEntry>.from(state.timeline)
          ..add(
            StudioAgentTimelineEntry(
              id: _nextEntryId(),
              kind: StudioAgentTimelineKind.stepSuggestion,
              pipelineStep: step,
              suggestionLabel: label,
              suggestionReason: reason,
            ),
          );
        final suggestions = List<StudioAgentStepSuggestion>.from(
          state.pendingStepSuggestions,
        );
        if (!suggestions.any((item) => item.step == step)) {
          suggestions.add(
            StudioAgentStepSuggestion(step: step, label: label, reason: reason),
          );
        }
        state = state.copyWith(
          timeline: timeline,
          pendingStepSuggestions: suggestions,
        );
      case StudioAgentStreamDone():
        state = state.copyWith(isStreaming: false);
    }
  }

  /// Advances the pipeline when [stepName] is unlocked.
  bool applyStepSuggestion(String stepName) {
    final unlocked = ref.read(unlockedStepsProvider);
    if (!unlocked.contains(stepName)) {
      state = state.copyWith(
        errorMessage: 'Complete earlier Studio steps before opening $stepName.',
      );
      return false;
    }
    ref.read(workspaceProvider.notifier).setActivePipelineStep(stepName);
    state = state.copyWith(
      pendingStepSuggestions: state.pendingStepSuggestions
          .where((item) => item.step != stepName)
          .toList(growable: false),
      clearError: true,
    );
    return true;
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final studioAgentNotifierProvider =
    NotifierProvider<StudioAgentNotifier, StudioAgentState>(
      StudioAgentNotifier.new,
    );
