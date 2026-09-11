import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class ModuleDeploymentFieldSpec {
  const ModuleDeploymentFieldSpec({
    required this.moduleId,
    required this.moduleName,
    required this.key,
    required this.isSecret,
  });

  final String moduleId;
  final String moduleName;
  final String key;
  final bool isSecret;
}

/// Loads module env/secret requirements from the bundled manifest.
Future<List<ModuleDeploymentFieldSpec>> loadModuleDeploymentFieldSpecs() async {
  final raw = await rootBundle.loadString('assets/modules.json');
  final decoded = jsonDecode(raw);
  if (decoded is! List<dynamic>) return const [];
  final specs = <ModuleDeploymentFieldSpec>[];
  for (final entry in decoded.whereType<Map<String, dynamic>>()) {
    final module = Module.fromJson(entry);
    final deployment = module.deployment;
    if (deployment == null) continue;
    for (final key in deployment.requiredEnvironment) {
      specs.add(
        ModuleDeploymentFieldSpec(
          moduleId: module.id,
          moduleName: module.name,
          key: key,
          isSecret: false,
        ),
      );
    }
    for (final key in deployment.secretFields) {
      specs.add(
        ModuleDeploymentFieldSpec(
          moduleId: module.id,
          moduleName: module.name,
          key: key,
          isSecret: true,
        ),
      );
    }
  }
  specs.sort((left, right) {
    final byModule = left.moduleName.compareTo(right.moduleName);
    if (byModule != 0) return byModule;
    return left.key.compareTo(right.key);
  });
  return specs;
}

/// Backend Setup fields for per-module env vars declared in [modules.json].
class ModuleDeploymentFields extends StatefulWidget {
  const ModuleDeploymentFields({
    super.key,
    required this.values,
    required this.secretValues,
    required this.onChanged,
  });

  final Map<String, String> values;
  final Map<String, String> secretValues;
  final void Function(Map<String, String> values, Map<String, String> secrets)
  onChanged;

  @override
  State<ModuleDeploymentFields> createState() => _ModuleDeploymentFieldsState();
}

class _ModuleDeploymentFieldsState extends State<ModuleDeploymentFields> {
  late Future<List<ModuleDeploymentFieldSpec>> _specsFuture;
  final _controllers = <String, TextEditingController>{};
  final _obscured = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _specsFuture = loadModuleDeploymentFieldSpecs();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(ModuleDeploymentFieldSpec spec) {
    return _controllers.putIfAbsent(
      spec.key,
      () => TextEditingController(
        text: spec.isSecret
            ? widget.secretValues[spec.key] ?? ''
            : widget.values[spec.key] ?? '',
      ),
    );
  }

  void _emitChange(ModuleDeploymentFieldSpec spec, String value) {
    final nextValues = Map<String, String>.from(widget.values);
    final nextSecrets = Map<String, String>.from(widget.secretValues);
    if (spec.isSecret) {
      if (value.isEmpty) {
        nextSecrets.remove(spec.key);
      } else {
        nextSecrets[spec.key] = value;
      }
    } else if (value.isEmpty) {
      nextValues.remove(spec.key);
    } else {
      nextValues[spec.key] = value;
    }
    widget.onChanged(nextValues, nextSecrets);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    return FutureBuilder<List<ModuleDeploymentFieldSpec>>(
      future: _specsFuture,
      builder: (context, snapshot) {
        final specs = snapshot.data ?? const <ModuleDeploymentFieldSpec>[];
        if (specs.isEmpty) {
          return const SizedBox.shrink();
        }
        final byModule = <String, List<ModuleDeploymentFieldSpec>>{};
        for (final spec in specs) {
          byModule.putIfAbsent(spec.moduleName, () => []).add(spec);
        }
        return NmtkSurfaceCard(
          padding: EdgeInsets.all(tokens.sectionGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Module configuration',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SizedBox(height: tokens.compactGap),
              const Text(
                'Optional settings for specific modules. You can fill these '
                'now or later from Backend Setup.',
              ),
              SizedBox(height: tokens.sectionGap),
              for (final moduleName in byModule.keys) ...[
                Text(moduleName, style: Theme.of(context).textTheme.titleSmall),
                SizedBox(height: tokens.compactGap),
                for (final spec in byModule[moduleName]!) ...[
                  Text(spec.key),
                  SizedBox(height: tokens.compactGap / 2),
                  NmtkTextInput(
                    key: Key('module-env-${spec.key}'),
                    controller: _controllerFor(spec),
                    obscureText:
                        spec.isSecret && (_obscured[spec.key] ?? true),
                    hintText: spec.isSecret
                        ? 'Secret value'
                        : 'Value for ${spec.key}',
                    onChange: (value) => _emitChange(spec, value ?? ''),
                    suffix: spec.isSecret
                        ? ZetaIconButton.text(
                            icon: (_obscured[spec.key] ?? true)
                                ? ZetaIcons.visibility_off
                                : ZetaIcons.visibility,
                            semanticLabel: (_obscured[spec.key] ?? true)
                                ? 'Show secret'
                                : 'Hide secret',
                            onPressed: () => setState(
                              () => _obscured[spec.key] =
                                  !(_obscured[spec.key] ?? true),
                            ),
                          )
                        : null,
                  ),
                  SizedBox(height: tokens.sectionGap),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}
