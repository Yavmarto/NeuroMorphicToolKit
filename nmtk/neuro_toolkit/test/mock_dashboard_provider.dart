import 'dart:async';
import 'package:flutter/material.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/services/update_service.dart';

class MockDashboardProvider extends ChangeNotifier implements ModuleProvider {
  final List<Module> _mockModules = [];
  final List<String> launchCalls = [];
  final List<String> stopCalls = [];
  final List<String> uninstallCalls = [];

  @override
  List<Module> get installedModules =>
      _mockModules.where((m) => m.status != ModuleStatus.notInstalled).toList();

  @override
  List<Module> get modules => _mockModules;
  @override
  set modules(List<Module> val) {
    _mockModules.clear();
    _mockModules.addAll(val);
    notifyListeners();
  }

  @override
  List<Module> modulesForTesting = [];
  @override
  bool get isLoading => false;
  @override
  bool get pythonAvailable => true;
  @override
  String? get error => null;
  @override
  LauncherUpdate? get pendingLauncherUpdate => null;
  @override
  UpdateChannel get currentChannel => UpdateChannel.stable;
  @override
  List<String> get activeModuleIds => [];
  @override
  List<Module> get activeModules => [];
  @override
  List<Module> get availableModules => [];
  @override
  Future<void> recheckPython() async {}
  @override
  bool isMuJoCoAvailable() => false;
  @override
  Future<void> installModule(String moduleId) async {}
  @override
  void closeTab(String moduleId) {}
  @override
  Stream<String>? getModuleOutput(String moduleId) => null;

  @override
  Future<void> launchModule(String moduleId) async {
    launchCalls.add(moduleId);
  }

  @override
  Future<void> stopModule(String moduleId) async {
    stopCalls.add(moduleId);
  }

  @override
  Future<void> uninstallModule(String moduleId) async {
    uninstallCalls.add(moduleId);
  }

  @override
  Future<void> checkForUpdates() async {}

  @override
  Future<void> updateModule(String moduleId) async {}

  @override
  void setUpdateChannel(UpdateChannel channel) {}

  @override
  Future<void> setVersionPinned(String moduleId, bool pinned) async {}

  @override
  void dismissLauncherUpdate() {}

  void setInstalledModules(List<Module> modules) {
    _mockModules.clear();
    _mockModules.addAll(modules);
    notifyListeners();
  }

  @override
  Future<void> updateModuleSettings(
    String id, {
    bool? isEnabled,
    int? customPort,
    bool? startOnLaunch,
  }) async {}

  @override
  void updateSettingsProvider(dynamic settingsProvider) {}
}
