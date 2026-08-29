import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

void main() {
  test('maps Studio teensy target to Neurochip teensy workspace', () {
    final target = StudioNeurochipHandoffContract.fromStudioTargetId('teensy');

    expect(target.neurochipTargetId, 'teensy41');
    expect(target.targetLabel, 'Teensy 4.1');
    expect(target.destinationWorkspace, 'teensy');
  });

  test('maps Studio pynq target to Neurochip pynq workspace', () {
    final target = StudioNeurochipHandoffContract.fromStudioTargetId('pynq');

    expect(target.neurochipTargetId, 'pynq');
    expect(target.targetLabel, 'PYNQ');
    expect(target.destinationWorkspace, 'pynq');
  });

  test('maps Studio akida target to Neurochip akida workspace', () {
    final target = StudioNeurochipHandoffContract.fromStudioTargetId('akida');

    expect(target.neurochipTargetId, 'akida');
    expect(target.targetLabel, 'Akida');
    expect(target.destinationWorkspace, 'akida');
  });

  test('falls back to the default target mapping for unknown ids', () {
    final target = StudioNeurochipHandoffContract.fromStudioTargetId('unknown');

    expect(target, same(StudioNeurochipHandoffContract.fallback));
    expect(target.neurochipTargetId, 'teensy41');
  });
}
