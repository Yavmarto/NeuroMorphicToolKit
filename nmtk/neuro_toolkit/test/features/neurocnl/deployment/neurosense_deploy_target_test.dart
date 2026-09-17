import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_target_catalog/support.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/setup_step/support.dart';

void main() {
  test('neurosense is a live sensor source, not a deploy target', () {
    expect(deployTargets.any((t) => t.id == 'neurosense'), isFalse);

    final source = sensorSourceForId('neurosense');
    expect(source, isNotNull);
    expect(source!.label, contains('NeuroSense'));
  });

  test('neurosense does not use the SSH-paired hardware manage flow', () {
    expect(isHardwareTargetWithManageFlowId('neurosense'), isFalse);
  });
}
