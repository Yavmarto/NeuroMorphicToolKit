import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/services/cross_module_navigation.dart';

void main() {
  final modules = [
    Module(
      id: 'neurocnl',
      name: 'NeuroStudio',
      description: 'CNL',
      directory: 'neurocnl',
      port: 8000,
      hasFrontend: true,
    ),
    Module(
      id: 'Neurochip',
      name: 'NeuroChip',
      description: 'Hardware',
      directory: 'Neurochip',
      port: 8002,
      hasFrontend: true,
    ),
  ];

  test('resolveCrossModuleNavigation detects a different module port', () {
    final navigation = resolveCrossModuleNavigation(
      targetUri: Uri.parse('http://localhost:8002/?import_cnl=abc123'),
      modules: modules,
      currentModuleId: 'neurocnl',
    );

    expect(navigation, isNotNull);
    expect(navigation!.targetModule.id, 'Neurochip');
    expect(navigation.targetUri.queryParameters['import_cnl'], 'abc123');
  });

  test('resolveCrossModuleNavigation ignores same-module navigation', () {
    final navigation = resolveCrossModuleNavigation(
      targetUri: Uri.parse('http://localhost:8000/deploy'),
      modules: modules,
      currentModuleId: 'neurocnl',
    );

    expect(navigation, isNull);
  });

  test('launcherDeepLinkFromUri preserves query and fragment', () {
    final deepLink = launcherDeepLinkFromUri(
      Uri.parse('http://localhost:8002/handoff?import_network=abc123#dock'),
    );

    expect(deepLink, '/handoff?import_network=abc123#dock');
  });
}
