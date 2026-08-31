import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _forbiddenImports = <String>[
  'package:flutter_riverpod/',
  'package:riverpod/',
  'package:provider/',
  'package:go_router/',
  'package:dio/',
  'package:http/',
  'package:shared_preferences/',
  'package:flutter_secure_storage/',
];

const _neurocnlOnlyExports = <String>[
  'models/energy_report.dart',
  'models/quantization_report.dart',
  'models/sensor_frame.dart',
  'models/bulk_spike_frame.dart',
  'widgets/backend_support_banner.dart',
  'widgets/energy_bar_chart.dart',
  'widgets/quantization_table.dart',
  'widgets/pipeline_stepper.dart',
  'widgets/snn_workflow_stepper.dart',
  'widgets/snn_mobile_workflow_stepper.dart',
  'widgets/pynq_deploy_status_card.dart',
  'widgets/akida_support_state_card.dart',
  'widgets/deploy_layout.dart',
  'widgets/workspace_shell.dart',
];

void main() {
  test('shared UI stays independent of app services and state management', () {
    // Scoped to lib/ui_core/ — this rule governs the shared UI toolkit, not
    // root's own app code (which legitimately uses riverpod/go_router/etc).
    final sources = Directory('lib/ui_core')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final source in sources) {
      final contents = source.readAsStringSync();
      for (final forbiddenImport in _forbiddenImports) {
        expect(
          contents.contains(forbiddenImport),
          isFalse,
          reason: '${source.path} imports $forbiddenImport',
        );
      }
    }
  });

  test('the public barrel excludes NeuroCNL-only presentation APIs', () {
    final barrel = File('lib/ui_core/nmtk_ui_core.dart').readAsStringSync();
    for (final export in _neurocnlOnlyExports) {
      expect(barrel.contains("export '$export'"), isFalse, reason: export);
    }

    expect(barrel, contains("export 'models/pynq_deployment_model.dart'"));
    expect(barrel, contains("export 'models/akida_deployment_model.dart'"));
  });
}
