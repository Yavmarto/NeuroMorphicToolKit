// Unit tests for ScNeuroCoreTargetService.
//
// Verifies: CRUD round-trips through a mock SharedPreferences, default
// auto-demotion, and empty-state handling.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/sc_neurocore_synthesis_target.dart';
import 'package:neuro_toolkit/features/neurocnl/services/sc_neurocore_target_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ScNeuroCoreTargetService', () {
    // ── fetchTargets ────────────────────────────────────────────────────────

    test('fetchTargets returns empty list when prefs are empty', () async {
      final service = ScNeuroCoreTargetService();
      final targets = await service.fetchTargets();
      expect(targets, isEmpty);
    });

    // ── saveTarget — create ──────────────────────────────────────────────────

    test(
      'saveTarget creates a target with a generated id when id is empty',
      () async {
        final service = ScNeuroCoreTargetService();
        final saved = await service.saveTarget(
          const ScNeuroCoreTarget(
            id: '',
            displayName: 'My iCE40',
            family: ScNeuroCoreFamily.ice40,
            deviceSpec: 'hx8k-ct256',
            toolchain: ScNeuroCoreToolchain.yosysNextpnr,
          ),
        );
        expect(saved.id, isNotEmpty);
        expect(saved.id.startsWith('sc_nc_'), isTrue);
      },
    );

    test('saveTarget persists target so fetchTargets returns it', () async {
      final service = ScNeuroCoreTargetService();
      await service.saveTarget(
        const ScNeuroCoreTarget(
          id: '',
          displayName: 'ECP5 board',
          family: ScNeuroCoreFamily.ecp5,
          deviceSpec: 'LFE5U-85F',
          toolchain: ScNeuroCoreToolchain.yosysNextpnr,
        ),
      );
      final targets = await service.fetchTargets();
      expect(targets, hasLength(1));
      expect(targets.first.displayName, 'ECP5 board');
      expect(targets.first.family, ScNeuroCoreFamily.ecp5);
    });

    // ── saveTarget — update ──────────────────────────────────────────────────

    test('saveTarget with existing id updates the entry in place', () async {
      final service = ScNeuroCoreTargetService();
      final original = await service.saveTarget(
        const ScNeuroCoreTarget(
          id: '',
          displayName: 'Old name',
          family: ScNeuroCoreFamily.xilinx,
          deviceSpec: 'xc7a35t-cpg236-1',
          toolchain: ScNeuroCoreToolchain.vivado,
        ),
      );
      await service.saveTarget(original.copyWith(displayName: 'New name'));
      final targets = await service.fetchTargets();
      expect(targets, hasLength(1));
      expect(targets.first.displayName, 'New name');
    });

    // ── default auto-demotion ────────────────────────────────────────────────

    test('saving a default target demotes other defaults', () async {
      final service = ScNeuroCoreTargetService();
      final first = await service.saveTarget(
        const ScNeuroCoreTarget(
          id: '',
          displayName: 'First',
          family: ScNeuroCoreFamily.ice40,
          deviceSpec: 'hx8k-ct256',
          toolchain: ScNeuroCoreToolchain.yosysNextpnr,
          isDefault: true,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Save a second target as default.
      await service.saveTarget(
        const ScNeuroCoreTarget(
          id: '',
          displayName: 'Second',
          family: ScNeuroCoreFamily.ecp5,
          deviceSpec: 'LFE5U-85F',
          toolchain: ScNeuroCoreToolchain.yosysNextpnr,
          isDefault: true,
        ),
      );
      final targets = await service.fetchTargets();
      final firstUpdated = targets.firstWhere((t) => t.id == first.id);
      final second = targets.firstWhere((t) => t.displayName == 'Second');
      expect(
        firstUpdated.isDefault,
        isFalse,
        reason: 'First target must be demoted when second is set as default',
      );
      expect(second.isDefault, isTrue);
    });

    // ── deleteTarget ─────────────────────────────────────────────────────────

    test('deleteTarget removes the target from prefs', () async {
      final service = ScNeuroCoreTargetService();
      final saved = await service.saveTarget(
        const ScNeuroCoreTarget(
          id: '',
          displayName: 'To delete',
          family: ScNeuroCoreFamily.intel,
          deviceSpec: '',
          toolchain: ScNeuroCoreToolchain.quartus,
        ),
      );
      await service.deleteTarget(saved.id);
      final targets = await service.fetchTargets();
      expect(targets, isEmpty);
    });

    test('deleteTarget is a no-op for an unknown id', () async {
      final service = ScNeuroCoreTargetService();
      await service.saveTarget(
        const ScNeuroCoreTarget(
          id: '',
          displayName: 'Survivor',
          family: ScNeuroCoreFamily.gowin,
          deviceSpec: '',
          toolchain: ScNeuroCoreToolchain.yosysNextpnr,
        ),
      );
      await service.deleteTarget('nonexistent_id');
      final targets = await service.fetchTargets();
      expect(targets, hasLength(1));
    });

    // ── JSON round-trip ──────────────────────────────────────────────────────

    test('ScNeuroCoreTarget serialises and deserialises correctly (local)', () {
      const original = ScNeuroCoreTarget(
        id: 'test_id_123',
        displayName: 'Vivado Xilinx',
        family: ScNeuroCoreFamily.xilinx,
        deviceSpec: 'xc7a100t-csg324-1',
        toolchain: ScNeuroCoreToolchain.vivado,
        deploymentMode: ScNeuroCoreDeploymentMode.local,
        toolchainBinPath: '/opt/Xilinx/Vivado/2023.2/bin/vivado',
        outputDirectory: '/home/user/rtl_out',
        isDefault: true,
      );
      final json = original.toJson();
      final decoded = ScNeuroCoreTarget.fromJson(json);
      expect(decoded.id, original.id);
      expect(decoded.displayName, original.displayName);
      expect(decoded.family, original.family);
      expect(decoded.deviceSpec, original.deviceSpec);
      expect(decoded.toolchain, original.toolchain);
      expect(decoded.deploymentMode, original.deploymentMode);
      expect(decoded.toolchainBinPath, original.toolchainBinPath);
      expect(decoded.outputDirectory, original.outputDirectory);
      expect(decoded.isDefault, original.isDefault);
    });

    test(
      'ScNeuroCoreTarget serialises and deserialises correctly (network)',
      () {
        const original = ScNeuroCoreTarget(
          id: 'test_id_net',
          displayName: 'PYNQ-Z2 Network',
          family: ScNeuroCoreFamily.xilinx,
          deviceSpec: 'xc7z020',
          toolchain: ScNeuroCoreToolchain.vivado,
          deploymentMode: ScNeuroCoreDeploymentMode.network,
          host: '198.51.100.100',
          sshPort: 2222,
          username: 'xilinx',
          sshKeyPath: '/home/user/.ssh/id_rsa',
        );
        final json = original.toJson();
        final decoded = ScNeuroCoreTarget.fromJson(json);
        expect(decoded.id, original.id);
        expect(decoded.deploymentMode, original.deploymentMode);
        expect(decoded.host, original.host);
        expect(decoded.sshPort, original.sshPort);
        expect(decoded.username, original.username);
        expect(decoded.sshKeyPath, original.sshKeyPath);
      },
    );

    // ── compatibleWith toolchain filter ──────────────────────────────────────

    test('ice40 family is only compatible with yosys_nextpnr', () {
      final toolchains = ScNeuroCoreToolchain.compatibleWith(
        ScNeuroCoreFamily.ice40,
      );
      expect(toolchains, [ScNeuroCoreToolchain.yosysNextpnr]);
    });

    test('xilinx family is compatible with yosys_nextpnr and vivado', () {
      final toolchains = ScNeuroCoreToolchain.compatibleWith(
        ScNeuroCoreFamily.xilinx,
      );
      expect(
        toolchains,
        containsAll([
          ScNeuroCoreToolchain.yosysNextpnr,
          ScNeuroCoreToolchain.vivado,
        ]),
      );
    });

    test('intel family is only compatible with quartus', () {
      final toolchains = ScNeuroCoreToolchain.compatibleWith(
        ScNeuroCoreFamily.intel,
      );
      expect(toolchains, [ScNeuroCoreToolchain.quartus]);
    });
  });
}
