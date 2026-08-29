// Model for SC-NeuroCore FPGA synthesis targets.
//
// SC-NeuroCore is a local synthesis workflow — it lowers a NIR model through
// a Rust IR compiler to SystemVerilog RTL + vendor bitstream.  Synthesis runs
// locally (Yosys/nextpnr, Vivado, Quartus, Radiant) targeting a specific FPGA
// family.  There is no SSH device pairing or PYNQ overlay in this path.

import 'package:flutter/material.dart';

/// FPGA device families supported by SC-NeuroCore's RTL emitter.
///
/// Maps to the values exposed by the upstream synthesis dashboard
/// (ice40 / ECP5 / Gowin / Xilinx / Intel).
enum ScNeuroCoreFamily {
  ice40,
  ecp5,
  gowin,
  xilinx,
  intel;

  static ScNeuroCoreFamily fromString(String? value) {
    switch (value) {
      case 'ice40':
        return ScNeuroCoreFamily.ice40;
      case 'ecp5':
        return ScNeuroCoreFamily.ecp5;
      case 'gowin':
        return ScNeuroCoreFamily.gowin;
      case 'xilinx':
        return ScNeuroCoreFamily.xilinx;
      case 'intel':
        return ScNeuroCoreFamily.intel;
      default:
        return ScNeuroCoreFamily.ice40;
    }
  }

  String get apiValue => name;

  String get label {
    switch (this) {
      case ScNeuroCoreFamily.ice40:
        return 'iCE40 (Lattice)';
      case ScNeuroCoreFamily.ecp5:
        return 'ECP5 (Lattice)';
      case ScNeuroCoreFamily.gowin:
        return 'Gowin';
      case ScNeuroCoreFamily.xilinx:
        return 'Xilinx';
      case ScNeuroCoreFamily.intel:
        return 'Intel (Quartus)';
    }
  }

  IconData get icon {
    switch (this) {
      case ScNeuroCoreFamily.ice40:
      case ScNeuroCoreFamily.ecp5:
      case ScNeuroCoreFamily.gowin:
        return Icons
            .developer_board_outlined; // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      case ScNeuroCoreFamily.xilinx:
      case ScNeuroCoreFamily.intel:
        return Icons
            .developer_board_sharp; // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    }
  }
}

/// Synthesis toolchains supported by SC-NeuroCore.
enum ScNeuroCoreToolchain {
  yosysNextpnr,
  vivado,
  quartus,
  radiant,
  diamond;

  static ScNeuroCoreToolchain fromString(String? value) {
    switch (value) {
      case 'yosys_nextpnr':
        return ScNeuroCoreToolchain.yosysNextpnr;
      case 'vivado':
        return ScNeuroCoreToolchain.vivado;
      case 'quartus':
        return ScNeuroCoreToolchain.quartus;
      case 'radiant':
        return ScNeuroCoreToolchain.radiant;
      case 'diamond':
        return ScNeuroCoreToolchain.diamond;
      default:
        return ScNeuroCoreToolchain.yosysNextpnr;
    }
  }

  String get apiValue {
    switch (this) {
      case ScNeuroCoreToolchain.yosysNextpnr:
        return 'yosys_nextpnr';
      case ScNeuroCoreToolchain.vivado:
        return 'vivado';
      case ScNeuroCoreToolchain.quartus:
        return 'quartus';
      case ScNeuroCoreToolchain.radiant:
        return 'radiant';
      case ScNeuroCoreToolchain.diamond:
        return 'diamond';
    }
  }

  String get label {
    switch (this) {
      case ScNeuroCoreToolchain.yosysNextpnr:
        return 'Yosys + nextpnr (open-source)';
      case ScNeuroCoreToolchain.vivado:
        return 'Vivado (Xilinx)';
      case ScNeuroCoreToolchain.quartus:
        return 'Quartus (Intel)';
      case ScNeuroCoreToolchain.radiant:
        return 'Radiant (Lattice)';
      case ScNeuroCoreToolchain.diamond:
        return 'Diamond (Lattice)';
    }
  }

  /// Returns the toolchains that are compatible with [family].
  static List<ScNeuroCoreToolchain> compatibleWith(ScNeuroCoreFamily family) {
    switch (family) {
      case ScNeuroCoreFamily.ice40:
      case ScNeuroCoreFamily.ecp5:
      case ScNeuroCoreFamily.gowin:
        return [ScNeuroCoreToolchain.yosysNextpnr];
      case ScNeuroCoreFamily.xilinx:
        return [ScNeuroCoreToolchain.yosysNextpnr, ScNeuroCoreToolchain.vivado];
      case ScNeuroCoreFamily.intel:
        return [ScNeuroCoreToolchain.quartus];
    }
  }
}

/// Deployment mode for SC-NeuroCore targets.
enum ScNeuroCoreDeploymentMode {
  local,
  network;

  static ScNeuroCoreDeploymentMode fromString(String? value) {
    if (value == 'network') {
      return ScNeuroCoreDeploymentMode.network;
    }
    return ScNeuroCoreDeploymentMode.local;
  }

  String get apiValue => name;
}

/// A locally-stored SC-NeuroCore synthesis target configuration.
///
/// Unlike Akida or PYNQ targets, this is never sent to a remote device.
/// It is persisted locally in [SharedPreferences] and used to configure the
/// SC-NeuroCore RTL compiler arguments.
class ScNeuroCoreTarget {
  const ScNeuroCoreTarget({
    required this.id,
    required this.displayName,
    required this.family,
    required this.deviceSpec,
    required this.toolchain,
    this.deploymentMode = ScNeuroCoreDeploymentMode.local,
    this.host = '',
    this.sshPort = 22,
    this.username = 'root',
    this.sshKeyPath = '',
    this.toolchainBinPath = '',
    this.outputDirectory = '',
    this.isDefault = false,
  });

  final String id;
  final String displayName;

  /// FPGA device family (ice40, ecp5, gowin, xilinx, intel).
  final ScNeuroCoreFamily family;

  /// Vendor device part, e.g. `hx8k-ct256`, `LFE5U-85F`, `xc7a35t-cpg236-1`.
  final String deviceSpec;

  /// Synthesis toolchain to invoke.
  final ScNeuroCoreToolchain toolchain;

  /// Target deployment mode (local file vs network SSH).
  final ScNeuroCoreDeploymentMode deploymentMode;

  /// Network host (for network deployment mode).
  final String host;

  /// SSH Port (for network deployment mode).
  final int sshPort;

  /// SSH Username (for network deployment mode).
  final String username;

  /// Path to SSH Private Key (for network deployment mode).
  final String sshKeyPath;

  /// Optional absolute path to the toolchain binary.
  ///
  /// This path always refers to the local filesystem of the server running
  /// the CNL Studio backend, regardless of [deploymentMode]. The synthesis
  /// step (Vivado, Yosys, Quartus) executes on the backend server. Leave
  /// blank to use the backend server's `$PATH`.
  final String toolchainBinPath;

  /// Directory where RTL and bitstream output will be written.  When empty the
  /// SC-NeuroCore default output directory is used.
  final String outputDirectory;

  /// Whether to auto-select this target on workspace open.
  final bool isDefault;

  /// Human-readable subtitle shown in the target list (host + state analogue).
  String get subtitle {
    final dev = deviceSpec.isEmpty ? 'no device' : deviceSpec;
    if (deploymentMode == ScNeuroCoreDeploymentMode.network) {
      return '${family.label} • $dev • ssh://$username@$host:$sshPort';
    }
    return '${family.label} • $dev';
  }

  factory ScNeuroCoreTarget.fromJson(Map<String, dynamic> json) {
    return ScNeuroCoreTarget(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'SC-NeuroCore Target',
      family: ScNeuroCoreFamily.fromString(json['family'] as String?),
      deviceSpec: json['deviceSpec'] as String? ?? '',
      toolchain: ScNeuroCoreToolchain.fromString(json['toolchain'] as String?),
      deploymentMode: ScNeuroCoreDeploymentMode.fromString(
        json['deploymentMode'] as String?,
      ),
      host: json['host'] as String? ?? '',
      sshPort: json['sshPort'] as int? ?? 22,
      username: json['username'] as String? ?? 'root',
      sshKeyPath: json['sshKeyPath'] as String? ?? '',
      toolchainBinPath: json['toolchainBinPath'] as String? ?? '',
      outputDirectory: json['outputDirectory'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'displayName': displayName,
      'family': family.apiValue,
      'deviceSpec': deviceSpec,
      'toolchain': toolchain.apiValue,
      'deploymentMode': deploymentMode.apiValue,
      if (host.isNotEmpty) 'host': host,
      'sshPort': sshPort,
      if (username.isNotEmpty) 'username': username,
      if (sshKeyPath.isNotEmpty) 'sshKeyPath': sshKeyPath,
      if (toolchainBinPath.isNotEmpty) 'toolchainBinPath': toolchainBinPath,
      if (outputDirectory.isNotEmpty) 'outputDirectory': outputDirectory,
      'isDefault': isDefault,
    };
  }

  ScNeuroCoreTarget copyWith({
    String? id,
    String? displayName,
    ScNeuroCoreFamily? family,
    String? deviceSpec,
    ScNeuroCoreToolchain? toolchain,
    ScNeuroCoreDeploymentMode? deploymentMode,
    String? host,
    int? sshPort,
    String? username,
    String? sshKeyPath,
    String? toolchainBinPath,
    String? outputDirectory,
    bool? isDefault,
  }) {
    return ScNeuroCoreTarget(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      family: family ?? this.family,
      deviceSpec: deviceSpec ?? this.deviceSpec,
      toolchain: toolchain ?? this.toolchain,
      deploymentMode: deploymentMode ?? this.deploymentMode,
      host: host ?? this.host,
      sshPort: sshPort ?? this.sshPort,
      username: username ?? this.username,
      sshKeyPath: sshKeyPath ?? this.sshKeyPath,
      toolchainBinPath: toolchainBinPath ?? this.toolchainBinPath,
      outputDirectory: outputDirectory ?? this.outputDirectory,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
