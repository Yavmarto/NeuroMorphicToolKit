import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

part 'studio_view_mode_provider.g.dart';

/// Which pane is shown in the left editor workspace of NeuroStudio.
enum StudioViewMode { cnl, nir, canvas, network }

/// State for the editor view toggle.
///
/// Previously also carried an `isSyncing`/`syncError` in-flight indicator
/// toggled by the old three-way sync reconciler (studio_sync_notifier.dart).
/// That reconciler is gone — canonicalDocProvider is the only writer of
/// content now, and its own `AsyncLoading`/`AsyncError` state is the single
/// place to check for an in-flight mutation, so the duplicate indicator here
/// was removed rather than reconnected.
class StudioSyncState {
  final StudioViewMode viewMode;

  const StudioSyncState({this.viewMode = StudioViewMode.cnl});

  StudioSyncState copyWith({StudioViewMode? viewMode}) {
    return StudioSyncState(viewMode: viewMode ?? this.viewMode);
  }
}

@riverpod
class StudioViewModeController extends _$StudioViewModeController {
  static const _modeKey = 'studio_view_mode_v1';

  @override
  StudioSyncState build() {
    return StudioSyncState(viewMode: _loadPersistedMode());
  }

  static StudioViewMode _loadPersistedMode() {
    final stored = ServerConfigService.getString(_modeKey);
    if (stored == 'network') return StudioViewMode.network;
    if (stored == 'canvas') return StudioViewMode.canvas;
    if (stored == 'nir') return StudioViewMode.nir;
    return StudioViewMode.cnl;
  }

  void setMode(StudioViewMode mode) {
    ServerConfigService.setString(_modeKey, switch (mode) {
      StudioViewMode.network => 'network',
      StudioViewMode.canvas => 'canvas',
      StudioViewMode.nir => 'nir',
      StudioViewMode.cnl => 'cnl',
    });
    state = state.copyWith(viewMode: mode);
  }
}

/// Backward-compat alias consumed by existing widgets.
final studioViewModeProvider = studioViewModeControllerProvider;
