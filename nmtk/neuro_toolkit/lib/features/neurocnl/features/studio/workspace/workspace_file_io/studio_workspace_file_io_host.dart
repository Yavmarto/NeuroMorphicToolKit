import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The subset of `_StudioScreenState` that `WorkspaceFileIoController` needs.
///
/// Kept as an explicit interface (rather than reaching into private State
/// fields, which `WorkspaceFileIoController` cannot do once it lives in its
/// own library) so the controller's dependency on the host screen is typed
/// and minimal.
abstract class StudioWorkspaceFileIoHost {
  bool get mounted;
  BuildContext get context;
  WidgetRef get ref;
  Timer? get canvasAutosaveTimer;
  set canvasAutosaveTimer(Timer? value);
  bool get isOpeningWorkspace;
  set isOpeningWorkspace(bool value);
  void rebuild(VoidCallback fn);
}
