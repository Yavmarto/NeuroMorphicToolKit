import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/models/shell_models.dart';
import 'package:nmtk_ui_core/models/pynq_deployment_model.dart';
import 'package:nmtk_ui_core/models/akida_deployment_model.dart';

void main() {
  group('REQ-6.2: model-exposed IconData resolution', () {
    test('NmtkShellStatusSpec icons are non-null with fontFamily', () {
      for (final state in NmtkShellReadinessState.values) {
        final spec = NmtkShellStatusSpec.fromReadinessState(state);
        expect(
          spec.icon,
          isNotNull,
          reason: 'NmtkShellReadinessState.$state icon is null',
        );
        expect(
          spec.icon!.fontFamily,
          isNotNull,
          reason:
              'NmtkShellReadinessState.$state icon has null fontFamily '
              '(expected zeta-icons* or Material Icons)',
        );
      }
    });

    test('PynqSupportState icons are non-null with fontFamily', () {
      for (final state in PynqSupportState.values) {
        final icon = state.icon;
        expect(icon, isNotNull, reason: 'PynqSupportState.$state icon is null');
        expect(
          icon.fontFamily,
          isNotNull,
          reason: 'PynqSupportState.$state icon has null fontFamily',
        );
      }
    });

    test('AkidaSupportState icons are non-null with fontFamily', () {
      for (final state in AkidaSupportState.values) {
        final icon = state.icon;
        expect(
          icon,
          isNotNull,
          reason: 'AkidaSupportState.$state icon is null',
        );
        expect(
          icon.fontFamily,
          isNotNull,
          reason: 'AkidaSupportState.$state icon has null fontFamily',
        );
      }
    });
  });
}
