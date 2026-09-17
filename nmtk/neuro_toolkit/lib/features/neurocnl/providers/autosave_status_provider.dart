import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'autosave_status_provider.g.dart';

/// Drives the toolbar's ambient "Saving…" / "All changes saved" indicator.
enum AutosaveStatus { saving, saved }

/// Tracked as an in-flight counter (not a bool) because
/// `WorkspaceController._persist()` and `_scheduleCanvasAutosave()` are two
/// independent local-storage writers that can be in flight at the same time
/// — the indicator must only report "saved" once every writer has finished.
@riverpod
class AutosaveStatusController extends _$AutosaveStatusController {
  int _inFlight = 0;

  @override
  AutosaveStatus build() => AutosaveStatus.saved;

  void markSaveStarted() {
    _inFlight++;
    state = AutosaveStatus.saving;
  }

  void markSaveFinished() {
    _inFlight = _inFlight > 0 ? _inFlight - 1 : 0;
    if (_inFlight == 0) {
      state = AutosaveStatus.saved;
    }
  }
}

/// Short alias for the generated provider, matching the
/// `workspaceProvider`/`workspaceControllerProvider` convention.
final autosaveStatusProvider = autosaveStatusControllerProvider;
