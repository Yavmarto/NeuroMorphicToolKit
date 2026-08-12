import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LauncherNavigationAction {
  openWorkspace,
  openModule,
  reloadWorkspace,
  toggleSidebar,
}

class LauncherNavigationRequest {
  const LauncherNavigationRequest({
    required this.sequence,
    required this.action,
    this.moduleId,
  });

  final int sequence;
  final LauncherNavigationAction action;
  final String? moduleId;
}

final launcherNavigationProvider =
    NotifierProvider<LauncherNavigationNotifier, LauncherNavigationRequest?>(
  LauncherNavigationNotifier.new,
);

class LauncherNavigationNotifier extends Notifier<LauncherNavigationRequest?> {
  int _sequence = 0;

  @override
  LauncherNavigationRequest? build() => null;

  void openWorkspace() => _emit(LauncherNavigationAction.openWorkspace);

  void openModule(String moduleId) => _emit(
        LauncherNavigationAction.openModule,
        moduleId: moduleId,
      );

  void reloadWorkspace() => _emit(LauncherNavigationAction.reloadWorkspace);

  void toggleSidebar() => _emit(LauncherNavigationAction.toggleSidebar);

  void _emit(LauncherNavigationAction action, {String? moduleId}) {
    state = LauncherNavigationRequest(
      sequence: ++_sequence,
      action: action,
      moduleId: moduleId,
    );
  }
}
