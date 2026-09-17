import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/services/update_service.dart';

part 'module_state.freezed.dart';

@freezed
abstract class ModuleState with _$ModuleState {
  const factory ModuleState({
    @Default([]) List<Module> modules,
    @Default([]) List<String> activeModuleIds,
    @Default(true) bool pythonAvailable,
    @Default(true) bool mujocoAvailable,
    LauncherUpdate? pendingLauncherUpdate,
  }) = _ModuleState;

  const ModuleState._();

  List<Module> get installedModules => modules
      .where(
        (Module module) =>
            module.status == ModuleStatus.installed ||
            module.status == ModuleStatus.starting ||
            module.status == ModuleStatus.running ||
            module.status == ModuleStatus.stopping ||
            module.status == ModuleStatus.degraded ||
            module.status == ModuleStatus.error,
      )
      .toList();

  List<Module> get availableModules => modules
      .where(
        (Module module) =>
            module.status == ModuleStatus.notInstalled ||
            module.status == ModuleStatus.installing,
      )
      .toList();

  List<Module> get activeModules => activeModuleIds
      .map(
        (String id) => modules.firstWhere((Module module) => module.id == id),
      )
      .toList();
}
