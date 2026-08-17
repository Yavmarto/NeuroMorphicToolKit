// Data models for PYNQ Z2 export/deployment workflow.
//
// Mirrors the Python backend schemas from:
// - neurocnl PynqExportResult / PynqSupportState
// - Neurochip PYNQ backend (issue 11)
//
// Two-tier support model:
// - Exportable: toolkit can produce overlay artifacts offline (no board needed)
// - Deployable: overlay can be loaded onto real PYNQ hardware (runtime)

import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';

import 'package:nmtk_ui_core/models/trained_weight_status.dart';

/// Support state for PYNQ Z2 target.
///
/// Export-time states are deterministic at planning time.
/// Deploy-time states are resolved at runtime (issue #11).
enum PynqSupportState {
  /// All constraints met; overlay artifacts can be generated.
  exportable,

  /// Constraints met but near capacity thresholds (>80%).
  exportableWithWarnings,

  /// One or more export-blocking rejections present.
  notExportable,

  /// Export succeeded AND overlay loaded on real PYNQ board.
  deployable,

  /// Export OK but board unreachable or overlay load failed.
  notDeployable;

  static PynqSupportState fromString(String value) {
    switch (value) {
      case 'exportable':
        return PynqSupportState.exportable;
      case 'exportable_with_warnings':
        return PynqSupportState.exportableWithWarnings;
      case 'not_exportable':
        return PynqSupportState.notExportable;
      case 'deployable':
        return PynqSupportState.deployable;
      case 'not_deployable':
        return PynqSupportState.notDeployable;
      default:
        return PynqSupportState.notExportable;
    }
  }

  /// Human-readable label for UI display.
  String get label {
    switch (this) {
      case PynqSupportState.exportable:
        return 'Exportable — overlay package ready';
      case PynqSupportState.exportableWithWarnings:
        return 'Exportable — near capacity limits';
      case PynqSupportState.notExportable:
        return 'Not Exportable — see rejections';
      case PynqSupportState.deployable:
        return 'Deployed — running on PYNQ board';
      case PynqSupportState.notDeployable:
        return 'Not Deployable — board unreachable';
    }
  }

  /// Theme color for UI indicators, resolved from the suite's
  /// [NmtkShellTokens] semantic palette rather than a hardcoded hex value.
  ///
  /// Exportable-only (no warnings) maps to [NmtkShellTokens.runningColor] —
  /// the "works, not yet fully verified" in-progress tier; warnings map to
  /// [NmtkShellTokens.warningColor]; not-exportable/not-deployable map to
  /// [NmtkShellTokens.errorColor]; fully deployable maps to
  /// [NmtkShellTokens.healthyColor].
  Color colorFor(NmtkShellTokens tokens) {
    switch (this) {
      case PynqSupportState.exportable:
        return tokens.runningColor;
      case PynqSupportState.exportableWithWarnings:
        return tokens.warningColor;
      case PynqSupportState.notExportable:
        return tokens.errorColor;
      case PynqSupportState.deployable:
        return tokens.healthyColor;
      case PynqSupportState.notDeployable:
        return tokens.errorColor;
    }
  }

  /// Icon for UI indicators.
  IconData get icon {
    switch (this) {
      case PynqSupportState.exportable:
        return ZetaIcons.upload_file;
      case PynqSupportState.exportableWithWarnings:
        return ZetaIcons.warning_outline;
      case PynqSupportState.notExportable:
        return ZetaIcons.block;
      case PynqSupportState.deployable:
        return ZetaIcons.check_circle;
      case PynqSupportState.notDeployable:
        return ZetaIcons.cloud_off;
    }
  }
}

/// Runtime mode reported by the Neurochip PYNQ backend.
enum PynqBackendRuntimeMode {
  unknown,
  hardware,
  simulator;

  static PynqBackendRuntimeMode fromJson(Object? value) {
    switch ((value as String?)?.toLowerCase()) {
      case 'hardware':
        return PynqBackendRuntimeMode.hardware;
      case 'simulator':
        return PynqBackendRuntimeMode.simulator;
      default:
        return PynqBackendRuntimeMode.unknown;
    }
  }

  bool get isSimulator => this == PynqBackendRuntimeMode.simulator;
}

/// Typed deploy-time config for POST /hardware/pynq/deploy.
///
/// Keys the toolkit has no field for — `timestep_us` today — are kept in
/// [additionalFields] and sent back untouched, so adding one to the backend
/// contract does not silently drop it here.
class PynqDeployConfig {
  static const Set<String> _knownJsonKeys = <String>{
    'threshold',
    'bit_width',
    'scale_factor',
  };

  final double threshold;
  final int bitWidth;
  final double scaleFactor;
  final Map<String, dynamic> additionalFields;

  const PynqDeployConfig({
    required this.threshold,
    required this.bitWidth,
    required this.scaleFactor,
    this.additionalFields = const <String, dynamic>{},
  });

  factory PynqDeployConfig.fromJson(Map<String, dynamic> json) {
    final additionalFields = Map<String, dynamic>.from(json)
      ..removeWhere((key, _) => _knownJsonKeys.contains(key));
    return PynqDeployConfig(
      threshold: (json['threshold'] as num?)?.toDouble() ?? 1.0,
      bitWidth: json['bit_width'] as int? ?? 8,
      scaleFactor: (json['scale_factor'] as num?)?.toDouble() ?? 1.0,
      additionalFields: additionalFields,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...additionalFields,
      'threshold': threshold,
      'bit_width': bitWidth,
      'scale_factor': scaleFactor,
    };
  }
}

/// The overlay's register map, carried between backend and board unchanged.
///
/// This is a contract token, not UI data: the backend resolves it from the
/// built overlay's `.hwh`, and the board runtime rejects a deploy whose map is
/// not *equal* to the manifest it has installed. No screen reads a field of it.
///
/// It used to be modelled as typed overlay-v1 registers, which turned the
/// round-trip into a rewrite: v2's keys survived only as passengers while nine
/// v1 keys the backend never sent (`status_reg_offset`, `neuron_base_offset`,
/// `weight_base_offset`, the buffer addresses …) were invented from defaults
/// and posted to the board. Equality could never hold, so every deploy came
/// back `422 OVERLAY_REGISTER_MAP_MISMATCH` — with both real maps identical.
/// Whatever the toolkit does not understand has to survive the trip untouched.
class PynqRegisterMap {
  /// The map exactly as the backend sent it.
  final Map<String, dynamic> values;

  const PynqRegisterMap(this.values);

  factory PynqRegisterMap.fromJson(Map<String, dynamic> json) =>
      PynqRegisterMap(Map<String, dynamic>.from(json));

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(values);

  /// The DMA channel the engine streams through, for display and diagnostics.
  String get dmaChannel => values['dma_channel'] as String? ?? '';

  bool get isEmpty => values.isEmpty;
}

/// One weight matrix in the overlay's layer chain, as the board runtime sees it.
///
/// Overlay-v2 walks these in order, handing each layer's spikes to the next, and
/// they are the only source of truth for the network's shape on the board: the
/// engine has no neuron-count registers. [inputSize] on the first layer is
/// therefore what a run's input has to be sized against, and [outputSize] on the
/// last is how wide each output frame comes back.
class PynqLayerDescriptor {
  final int inputSize;
  final int outputSize;
  final int weightOffset;
  final int threshold;
  final int leakShift;
  final int refractory;
  final String source;
  final String target;

  const PynqLayerDescriptor({
    required this.inputSize,
    required this.outputSize,
    this.weightOffset = 0,
    this.threshold = 0,
    this.leakShift = 0,
    this.refractory = 0,
    this.source = '',
    this.target = '',
  });

  factory PynqLayerDescriptor.fromJson(Map<String, dynamic> json) {
    int intOr(String key, int fallback) =>
        (json[key] as num?)?.toInt() ?? fallback;
    return PynqLayerDescriptor(
      inputSize: intOr('input_size', 0),
      outputSize: intOr('output_size', 0),
      weightOffset: intOr('weight_offset', 0),
      threshold: intOr('threshold', 0),
      leakShift: intOr('leak_shift', 0),
      refractory: intOr('refractory', 0),
      source: json['source'] as String? ?? '',
      target: json['target'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'input_size': inputSize,
      'output_size': outputSize,
      'weight_offset': weightOffset,
      'threshold': threshold,
      'leak_shift': leakShift,
      'refractory': refractory,
      if (source.isNotEmpty) 'source': source,
      if (target.isNotEmpty) 'target': target,
    };
  }
}

/// Validated deploy payload returned by NeuroCNL for Neurochip's PYNQ router.
class PynqDeployPayload {
  static const Set<String> _knownJsonKeys = <String>{
    'weights',
    'config',
    'layers',
    'bitstream_path',
    'overlay_id',
    'overlay_version',
    'weight_bit_width',
    'max_supported_neurons',
    'max_supported_synapses',
    'dma_ip_name',
    'snn_ip_name',
    'require_hardware',
    'register_map',
  };

  final List<double> weights;
  final PynqDeployConfig config;

  /// The overlay's layer chain, in execution order. Empty only for a payload
  /// built before the v2 handoff emitted them, which cannot run on the board.
  final List<PynqLayerDescriptor> layers;
  final String bitstreamPath;
  final String? overlayId;
  final String? overlayVersion;
  final int? weightBitWidth;
  final int? maxSupportedNeurons;
  final int? maxSupportedSynapses;
  final String? dmaIpName;
  final String? snnIpName;
  final bool requireHardware;
  final PynqRegisterMap registerMap;
  final Map<String, dynamic> additionalFields;

  const PynqDeployPayload({
    required this.weights,
    required this.config,
    this.layers = const <PynqLayerDescriptor>[],
    required this.bitstreamPath,
    this.overlayId,
    this.overlayVersion,
    this.weightBitWidth,
    this.maxSupportedNeurons,
    this.maxSupportedSynapses,
    this.dmaIpName,
    this.snnIpName,
    this.requireHardware = false,
    required this.registerMap,
    this.additionalFields = const <String, dynamic>{},
  });

  int get weightCount => weights.length;

  factory PynqDeployPayload.fromJson(Map<String, dynamic> json) {
    final additionalFields = Map<String, dynamic>.from(json)
      ..removeWhere((key, _) => _knownJsonKeys.contains(key));
    return PynqDeployPayload(
      weights: (json['weights'] as List? ?? const <Object>[])
          .map((e) => (e as num).toDouble())
          .toList(),
      config: PynqDeployConfig.fromJson(
        json['config'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      layers: (json['layers'] as List? ?? const <Object>[])
          .whereType<Map<String, dynamic>>()
          .map(PynqLayerDescriptor.fromJson)
          .toList(growable: false),
      bitstreamPath: json['bitstream_path'] as String? ?? 'snn_overlay.bit',
      overlayId: json['overlay_id'] as String?,
      overlayVersion: json['overlay_version'] as String?,
      weightBitWidth: json['weight_bit_width'] as int?,
      maxSupportedNeurons: json['max_supported_neurons'] as int?,
      maxSupportedSynapses: json['max_supported_synapses'] as int?,
      dmaIpName: json['dma_ip_name'] as String?,
      snnIpName: json['snn_ip_name'] as String?,
      requireHardware: json['require_hardware'] as bool? ?? false,
      registerMap: PynqRegisterMap.fromJson(
        json['register_map'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
      ),
      additionalFields: additionalFields,
    );
  }

  Map<String, dynamic> toJson() {
    final payload = <String, dynamic>{
      ...additionalFields,
      'weights': weights,
      'config': config.toJson(),
      'bitstream_path': bitstreamPath,
      'register_map': registerMap.toJson(),
    };
    // Omitted rather than sent empty: the board runtime derives every size from
    // this list, and an empty one has to fail as "no layers" instead of being
    // read as a deliberate zero-layer network.
    if (layers.isNotEmpty) {
      payload['layers'] = layers
          .map((layer) => layer.toJson())
          .toList(growable: false);
    }
    if (overlayId != null) payload['overlay_id'] = overlayId;
    if (overlayVersion != null) payload['overlay_version'] = overlayVersion;
    if (weightBitWidth != null) payload['weight_bit_width'] = weightBitWidth;
    if (maxSupportedNeurons != null) {
      payload['max_supported_neurons'] = maxSupportedNeurons;
    }
    if (maxSupportedSynapses != null) {
      payload['max_supported_synapses'] = maxSupportedSynapses;
    }
    if (dmaIpName != null) payload['dma_ip_name'] = dmaIpName;
    if (snnIpName != null) payload['snn_ip_name'] = snnIpName;
    if (requireHardware) payload['require_hardware'] = true;
    return payload;
  }
}

/// Where the deploy payload's weights came from.
///
/// The load-bearing field is `applied`. The CNL spec stores tensor *shape* only,
/// so without a trained NIR graph the payload's weights are all zeros: the board
/// loads the overlay, runs, and fires nothing. A UI that does not surface this
/// presents a zero-weight deploy as a successful hardware result.
///
/// The software simulators report the same thing about the same artifact, so the
/// model itself lives in `trained_weight_status.dart`; this name is kept for the
/// PYNQ call sites.
typedef PynqTrainedWeightStatus = TrainedWeightStatus;

/// Response from PYNQ exportability planning endpoint.
class PynqNetworkResponse {
  final PynqSupportState supportState;
  final List<String> warnings;
  final List<String> rejectionReasons;
  final Map<String, dynamic>? networkSummary;
  final PynqDeployPayload? deployPayload;

  /// Provenance of [deployPayload]'s weights, or null when no trained NIR graph
  /// was supplied — in which case the weights are the spec's zeros.
  final PynqTrainedWeightStatus? trainedWeights;

  const PynqNetworkResponse({
    required this.supportState,
    required this.warnings,
    required this.rejectionReasons,
    this.networkSummary,
    this.deployPayload,
    this.trainedWeights,
  });

  /// True when the payload carries learned values that will actually fire.
  bool get hasTrainedWeights =>
      trainedWeights?.applied == true && trainedWeights!.nonzero > 0;

  factory PynqNetworkResponse.fromJson(Map<String, dynamic> json) {
    return PynqNetworkResponse(
      supportState: PynqSupportState.fromString(
        json['support_state'] as String,
      ),
      warnings: (json['warnings'] as List).map((e) => e as String).toList(),
      rejectionReasons: (json['rejections'] as List)
          .map((e) => e as String)
          .toList(),
      networkSummary: json['network_summary'] as Map<String, dynamic>?,
      trainedWeights: json['trained_weights'] is Map<String, dynamic>
          ? PynqTrainedWeightStatus.fromJson(
              json['trained_weights'] as Map<String, dynamic>,
            )
          : null,
      deployPayload: json['deploy_payload'] is Map<String, dynamic>
          ? PynqDeployPayload.fromJson(
              json['deploy_payload'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

enum PynqBoardAuthMode {
  password,
  sshKey;

  static PynqBoardAuthMode fromString(String? value) {
    switch (value) {
      case 'ssh_key':
        return PynqBoardAuthMode.sshKey;
      case 'password':
      default:
        return PynqBoardAuthMode.password;
    }
  }

  String get apiValue {
    switch (this) {
      case PynqBoardAuthMode.password:
        return 'password';
      case PynqBoardAuthMode.sshKey:
        return 'ssh_key';
    }
  }
}

enum PynqBoardState {
  unpaired,
  reachable,
  provisioning,
  provisionFailed,
  runtimeInstalled,
  overlayMissing,
  ready,
  degradedOptionalCapability,
  preflightFailed,
  error;

  static PynqBoardState fromString(String? value) {
    switch (value) {
      case 'reachable':
        return PynqBoardState.reachable;
      case 'provisioning':
        return PynqBoardState.provisioning;
      case 'provision_failed':
        return PynqBoardState.provisionFailed;
      case 'runtime_installed':
        return PynqBoardState.runtimeInstalled;
      case 'overlay_missing':
        return PynqBoardState.overlayMissing;
      case 'ready':
        return PynqBoardState.ready;
      case 'degraded_optional_capability':
        return PynqBoardState.degradedOptionalCapability;
      case 'preflight_failed':
        return PynqBoardState.preflightFailed;
      case 'error':
        return PynqBoardState.error;
      case 'unpaired':
      default:
        return PynqBoardState.unpaired;
    }
  }

  String get apiValue {
    switch (this) {
      case PynqBoardState.unpaired:
        return 'unpaired';
      case PynqBoardState.reachable:
        return 'reachable';
      case PynqBoardState.provisioning:
        return 'provisioning';
      case PynqBoardState.provisionFailed:
        return 'provision_failed';
      case PynqBoardState.runtimeInstalled:
        return 'runtime_installed';
      case PynqBoardState.overlayMissing:
        return 'overlay_missing';
      case PynqBoardState.ready:
        return 'ready';
      case PynqBoardState.degradedOptionalCapability:
        return 'degraded_optional_capability';
      case PynqBoardState.preflightFailed:
        return 'preflight_failed';
      case PynqBoardState.error:
        return 'error';
    }
  }

  String get label {
    switch (this) {
      // The stored state a board is created with, before anything has contacted
      // it. "Unpaired" was the wrong word for it: a record only exists because
      // the user paired the board, so the label contradicted the screen it was
      // shown on. Nothing that has no board at all reaches this label — both
      // the Setup dot and the PYNQ setup pane branch on a null board first.
      case PynqBoardState.unpaired:
        return 'Not checked yet';
      case PynqBoardState.reachable:
        return 'Reachable';
      case PynqBoardState.provisioning:
        return 'Provisioning';
      case PynqBoardState.provisionFailed:
        return 'Provision Failed';
      case PynqBoardState.runtimeInstalled:
        return 'Runtime Installed';
      case PynqBoardState.overlayMissing:
        return 'Overlay Missing';
      case PynqBoardState.ready:
        return 'Ready';
      case PynqBoardState.degradedOptionalCapability:
        return 'Degraded Optional Capability';
      case PynqBoardState.preflightFailed:
        return 'Preflight Failed';
      case PynqBoardState.error:
        return 'Error';
    }
  }
}

class PynqPairedBoard {
  final String id;
  final String displayName;
  final String host;
  final int sshPort;
  final String username;
  final PynqBoardAuthMode authMode;
  final String credentialRef;
  final String runtimeApiUrl;
  final String runtimeApiUrlOverride;
  final String overlayVersion;
  final PynqBoardState state;
  final String lastPreflightStatus;
  final String lastPreflightMessage;
  final String lastRuntimeMode;
  final bool hasPassword;
  final String sshKeyPath;
  final bool isDefault;
  final Map<String, dynamic>? lastStatus;

  const PynqPairedBoard({
    required this.id,
    required this.displayName,
    required this.host,
    required this.sshPort,
    required this.username,
    required this.authMode,
    required this.credentialRef,
    required this.runtimeApiUrl,
    this.runtimeApiUrlOverride = '',
    required this.overlayVersion,
    required this.state,
    required this.lastPreflightStatus,
    required this.lastPreflightMessage,
    required this.lastRuntimeMode,
    required this.hasPassword,
    required this.sshKeyPath,
    this.isDefault = false,
    this.lastStatus,
  });

  bool get isReady => state == PynqBoardState.ready;

  factory PynqPairedBoard.fromJson(Map<String, dynamic> json) {
    return PynqPairedBoard(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'PYNQ Board',
      host: json['host'] as String? ?? '',
      sshPort: json['sshPort'] as int? ?? 22,
      username: json['username'] as String? ?? 'xilinx',
      authMode: PynqBoardAuthMode.fromString(json['authMode'] as String?),
      credentialRef: json['credentialRef'] as String? ?? '',
      runtimeApiUrl: json['runtimeApiUrl'] as String? ?? '',
      runtimeApiUrlOverride: json['runtimeApiUrlOverride'] as String? ?? '',
      overlayVersion: json['overlayVersion'] as String? ?? '',
      state: PynqBoardState.fromString(json['state'] as String?),
      lastPreflightStatus: json['lastPreflightStatus'] as String? ?? '',
      lastPreflightMessage: json['lastPreflightMessage'] as String? ?? '',
      lastRuntimeMode: json['lastRuntimeMode'] as String? ?? '',
      hasPassword: json['hasPassword'] as bool? ?? false,
      sshKeyPath: json['sshKeyPath'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
      lastStatus: json['lastStatus'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson({String? password}) {
    return <String, dynamic>{
      'id': id,
      'displayName': displayName,
      'host': host,
      'sshPort': sshPort,
      'username': username,
      'authMode': authMode.apiValue,
      'credentialRef': credentialRef,
      if (password != null && password.isNotEmpty) 'password': password,
      if (sshKeyPath.isNotEmpty) 'sshKeyPath': sshKeyPath,
      if (runtimeApiUrlOverride.isNotEmpty)
        'runtimeApiUrlOverride': runtimeApiUrlOverride,
      if (overlayVersion.isNotEmpty) 'overlayVersion': overlayVersion,
      'state': state.apiValue,
      'isDefault': isDefault,
    };
  }

  PynqPairedBoard copyWith({
    String? id,
    String? displayName,
    String? host,
    int? sshPort,
    String? username,
    PynqBoardAuthMode? authMode,
    String? credentialRef,
    String? runtimeApiUrl,
    String? runtimeApiUrlOverride,
    String? overlayVersion,
    PynqBoardState? state,
    String? lastPreflightStatus,
    String? lastPreflightMessage,
    String? lastRuntimeMode,
    bool? hasPassword,
    String? sshKeyPath,
    bool? isDefault,
    Map<String, dynamic>? lastStatus,
  }) {
    return PynqPairedBoard(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      host: host ?? this.host,
      sshPort: sshPort ?? this.sshPort,
      username: username ?? this.username,
      authMode: authMode ?? this.authMode,
      credentialRef: credentialRef ?? this.credentialRef,
      runtimeApiUrl: runtimeApiUrl ?? this.runtimeApiUrl,
      runtimeApiUrlOverride:
          runtimeApiUrlOverride ?? this.runtimeApiUrlOverride,
      overlayVersion: overlayVersion ?? this.overlayVersion,
      state: state ?? this.state,
      lastPreflightStatus: lastPreflightStatus ?? this.lastPreflightStatus,
      lastPreflightMessage: lastPreflightMessage ?? this.lastPreflightMessage,
      lastRuntimeMode: lastRuntimeMode ?? this.lastRuntimeMode,
      hasPassword: hasPassword ?? this.hasPassword,
      sshKeyPath: sshKeyPath ?? this.sshKeyPath,
      isDefault: isDefault ?? this.isDefault,
      lastStatus: lastStatus ?? this.lastStatus,
    );
  }
}

// ---------------------------------------------------------------------------
// Launcher-control board operations
// ---------------------------------------------------------------------------

/// Acknowledgement from POST /hardware/pynq/deploy.
///
/// [runtimeMode] is the load-bearing field: the same 200 response comes back
/// whether the overlay was loaded onto a real Zynq-7000 or satisfied by the
/// board runtime's pure-Python simulator, and only this distinguishes them. Any
/// UI that claims hardware must check it — see `isHardware`.
class PynqDeployAck {
  final String status;
  final String message;
  final PynqBackendRuntimeMode runtimeMode;
  final String? preflightStatus;
  final String? overlayVersion;

  const PynqDeployAck({
    required this.status,
    required this.message,
    required this.runtimeMode,
    this.preflightStatus,
    this.overlayVersion,
  });

  bool get isHardware => runtimeMode == PynqBackendRuntimeMode.hardware;

  factory PynqDeployAck.fromJson(Map<String, dynamic> json) {
    return PynqDeployAck(
      status: json['status'] as String? ?? 'unknown',
      message: json['message'] as String? ?? '',
      runtimeMode: PynqBackendRuntimeMode.fromJson(json['runtime_mode']),
      preflightStatus: json['preflight_status'] as String?,
      overlayVersion: json['overlay_version'] as String?,
    );
  }
}

/// Readiness of the overlay package staged on the backend host.
///
/// Mirrors `StagedOverlayPackageStatus.to_dict()`. The launcher's Install
/// Overlay action copies these three files to the board over SCP, so when
/// [ready] is false the board can never leave `overlayMissing` — surface
/// [issues] rather than a bare failure.
class PynqStagedOverlayPackage {
  final String stagingDir;
  final bool bitstreamExists;
  final bool hwhExists;
  final bool manifestPresent;
  final bool manifestValid;
  final bool ready;
  final List<String> issues;

  const PynqStagedOverlayPackage({
    required this.stagingDir,
    required this.bitstreamExists,
    required this.hwhExists,
    required this.manifestPresent,
    required this.manifestValid,
    required this.ready,
    this.issues = const <String>[],
  });

  factory PynqStagedOverlayPackage.fromJson(Map<String, dynamic> json) {
    return PynqStagedOverlayPackage(
      stagingDir: json['stagingDir'] as String? ?? '',
      bitstreamExists: json['bitstreamExists'] as bool? ?? false,
      hwhExists: json['hwhExists'] as bool? ?? false,
      manifestPresent: json['manifestPresent'] as bool? ?? false,
      manifestValid: json['manifestValid'] as bool? ?? false,
      ready: json['ready'] as bool? ?? false,
      issues: (json['issues'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .toList(growable: false),
    );
  }
}

/// Outcome of a launcher-control board operation.
///
/// Provision, install-overlay, restart-runtime and preflight all answer with the
/// updated board plus operation-specific extras, and several of them report
/// trouble *without* failing the HTTP call — a provision that could not finish
/// returns `error`, a user-space install that could not restart returns
/// `warning`. Reading only the board would silently drop both, so callers get
/// them here alongside it.
class PynqBoardOperationResult {
  final PynqPairedBoard board;
  final String? error;
  final String? warning;
  final PynqStagedOverlayPackage? localOverlayPackage;
  final Map<String, dynamic>? preflight;

  const PynqBoardOperationResult({
    required this.board,
    this.error,
    this.warning,
    this.localOverlayPackage,
    this.preflight,
  });

  bool get succeeded => error == null;

  factory PynqBoardOperationResult.fromJson(Map<String, dynamic> json) {
    // `/connectivity-test` answers the serialized board directly, while the
    // other routes nest it under `board` — and a serialized board has its own
    // `host` key holding an address string, so sniff for the wrapper rather
    // than assuming either shape (same trap as `_akidaHostPayload`).
    final nested = json['board'];
    final boardJson = nested is Map<String, dynamic> ? nested : json;
    final overlay = json['localOverlayPackage'];
    return PynqBoardOperationResult(
      board: PynqPairedBoard.fromJson(boardJson),
      error: (json['error'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['error'] as String).trim(),
      warning: _firstNonEmpty(<dynamic>[
        json['warning'],
        json['overlayRestartWarning'],
      ]),
      localOverlayPackage: overlay is Map<String, dynamic>
          ? PynqStagedOverlayPackage.fromJson(overlay)
          : null,
      preflight: json['preflight'] as Map<String, dynamic>?,
    );
  }

  static String? _firstNonEmpty(List<dynamic> candidates) {
    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Deploy job status — mirrors /hardware/pynq/status
// ---------------------------------------------------------------------------

/// Lifecycle state of a PYNQ backend deploy job.
///
/// Maps to the backend's `PynqState` enum plus router-level states:
///   unloaded / not_initialised → [notInitialised]
///   loaded                     → [loaded]
///   deploying (UI-only)        → [deploying]
///   configured                 → [configured]
///   running                    → [running]
///   failed                     → [failed]
enum PynqDeployJobStatus {
  /// No deploy has been attempted yet (or backend is unloaded).
  notInitialised,

  /// Overlay loaded but weights not yet configured.
  loaded,

  /// Overlay is being loaded and weights written (UI-side state).
  deploying,

  /// Overlay loaded and backend is configured and ready to run.
  configured,

  /// Backend is actively running inference.
  running,

  /// Deploy failed.
  failed;

  static PynqDeployJobStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'not_initialised':
      case 'not_initialized':
      case 'unloaded':
        return PynqDeployJobStatus.notInitialised;
      case 'loaded':
        return PynqDeployJobStatus.loaded;
      case 'deploying':
        return PynqDeployJobStatus.deploying;
      case 'configured':
        return PynqDeployJobStatus.configured;
      case 'running':
        return PynqDeployJobStatus.running;
      case 'failed':
        return PynqDeployJobStatus.failed;
      default:
        return PynqDeployJobStatus.notInitialised;
    }
  }

  double get progressFraction {
    switch (this) {
      case PynqDeployJobStatus.notInitialised:
        return 0.0;
      case PynqDeployJobStatus.loaded:
        return 0.25;
      case PynqDeployJobStatus.deploying:
        return 0.5;
      case PynqDeployJobStatus.configured:
        return 1.0;
      case PynqDeployJobStatus.running:
        return 0.9;
      case PynqDeployJobStatus.failed:
        return 0.0;
    }
  }
}

/// Deploy status snapshot from GET /hardware/pynq/status.
class PynqDeployJob {
  final PynqDeployJobStatus status;
  final String? bitstreamPath;
  final PynqBackendRuntimeMode runtimeMode;
  final bool loopRunning;

  const PynqDeployJob({
    required this.status,
    this.bitstreamPath,
    this.runtimeMode = PynqBackendRuntimeMode.unknown,
    this.loopRunning = false,
  });

  factory PynqDeployJob.fromJson(Map<String, dynamic> json) {
    return PynqDeployJob(
      status: PynqDeployJobStatus.fromString(json['state'] as String),
      bitstreamPath: json['bitstream_path'] as String?,
      runtimeMode: PynqBackendRuntimeMode.fromJson(json['runtime_mode']),
      loopRunning: json['loop_running'] as bool? ?? false,
    );
  }
}

// ---------------------------------------------------------------------------
// SITL verification result — mirrors /hardware/pynq/verify
// ---------------------------------------------------------------------------

/// Per-step result from SITL verification.
class PynqSitlStepResult {
  final String label;
  final List<int> inputSpikes;
  final List<int> outputSpikes;
  final List<int>? expectedOutputSpikes;
  final bool passed;
  final double executionTimeUs;

  const PynqSitlStepResult({
    required this.label,
    required this.inputSpikes,
    required this.outputSpikes,
    this.expectedOutputSpikes,
    required this.passed,
    required this.executionTimeUs,
  });

  factory PynqSitlStepResult.fromJson(Map<String, dynamic> json) {
    return PynqSitlStepResult(
      label: json['label'] as String,
      inputSpikes: (json['input_spikes'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => (value as num).toInt())
          .toList(growable: false),
      outputSpikes:
          (json['output_spikes'] as List<dynamic>? ?? const <dynamic>[])
              .map((value) => (value as num).toInt())
              .toList(growable: false),
      expectedOutputSpikes: (json['expected_output_spikes'] as List<dynamic>?)
          ?.map((value) => (value as num).toInt())
          .toList(growable: false),
      passed: json['passed'] as bool,
      executionTimeUs: (json['execution_time_us'] as num).toDouble(),
    );
  }
}

/// Single PYNQ runtime run result from POST /hardware/pynq/run.
class PynqRunResult {
  final String status;

  /// The raw output stream: one word per output neuron per timestep, 1 for a
  /// spike. Overlay-v1 sent a list of neuron indices, which is why callers must
  /// never read this as "the neurons that fired" or its length as a spike
  /// count — ten zeros is a silent run, not ten spikes. Use [outputNeurons] to
  /// fold it back into frames.
  final List<int> outputSpikes;
  final int timesteps;
  final double executionTimeUs;

  /// Neurons per output frame, or 0 when the board did not say. Without it the
  /// stream cannot be split into timesteps.
  final int outputNeurons;

  /// Whether the engine asserted `ap_done` before the host read the buffer.
  /// False means the numbers below it were read from a kernel that never
  /// reported finishing, so they are not evidence of anything — the run still
  /// comes back `status: success`, which is why this has to be shown.
  final bool kernelReportedDone;

  const PynqRunResult({
    required this.status,
    required this.outputSpikes,
    required this.timesteps,
    required this.executionTimeUs,
    this.outputNeurons = 0,
    this.kernelReportedDone = true,
  });

  factory PynqRunResult.fromJson(Map<String, dynamic> json) {
    return PynqRunResult(
      status: json['status'] as String? ?? 'unknown',
      outputSpikes:
          (json['output_spikes'] as List<dynamic>? ?? const <dynamic>[])
              .map((value) => (value as num).toInt())
              .toList(growable: false),
      timesteps: (json['timesteps'] as num?)?.toInt() ?? 1,
      executionTimeUs: (json['execution_time_us'] as num?)?.toDouble() ?? 0.0,
      outputNeurons: (json['output_neurons'] as num?)?.toInt() ?? 0,
      // Absent means an older board runtime that did not report it; treating
      // that as "not done" would put a warning on every run it serves.
      kernelReportedDone: json['kernel_reported_done'] as bool? ?? true,
    );
  }

  /// Neurons per frame, falling back to the whole stream when the board did not
  /// report a width — a single frame is the only safe reading of an
  /// unsplittable stream.
  int get frameWidth {
    if (outputNeurons > 0) return outputNeurons;
    if (timesteps > 0 && outputSpikes.length % timesteps == 0) {
      return outputSpikes.length ~/ timesteps;
    }
    return outputSpikes.length;
  }

  /// Spikes per output neuron, summed over the run. This is the readout the
  /// model was trained against: the class is the neuron that fired most.
  List<int> get spikeCountsPerNeuron {
    final width = frameWidth;
    if (width <= 0) return const <int>[];
    final counts = List<int>.filled(width, 0);
    for (var index = 0; index < outputSpikes.length; index++) {
      counts[index % width] += outputSpikes[index];
    }
    return counts;
  }

  /// Total spikes across the whole run.
  int get totalSpikes => outputSpikes.fold<int>(0, (sum, value) => sum + value);

  /// The output neuron that spiked most, or null when nothing fired. Ties go to
  /// the lowest index, matching `argmax`.
  int? get predictedClass {
    final counts = spikeCountsPerNeuron;
    var best = -1;
    var bestCount = 0;
    for (var index = 0; index < counts.length; index++) {
      if (counts[index] > bestCount) {
        bestCount = counts[index];
        best = index;
      }
    }
    return best < 0 ? null : best;
  }
}

/// Full SITL verification result from POST /hardware/pynq/verify.
class PynqSitlVerifyResult {
  final bool passed;
  final int totalCases;
  final int passedCases;
  final double meanExecUs;
  final double maxExecUs;
  final String summary;
  final List<PynqSitlStepResult> steps;

  const PynqSitlVerifyResult({
    required this.passed,
    required this.totalCases,
    required this.passedCases,
    required this.meanExecUs,
    required this.maxExecUs,
    required this.summary,
    required this.steps,
  });

  factory PynqSitlVerifyResult.fromJson(Map<String, dynamic> json) {
    return PynqSitlVerifyResult(
      passed: json['passed'] as bool,
      totalCases: json['total_cases'] as int,
      passedCases: json['passed_cases'] as int,
      meanExecUs: (json['mean_exec_us'] as num).toDouble(),
      maxExecUs: (json['max_exec_us'] as num).toDouble(),
      summary: json['summary'] as String,
      steps: (json['steps'] as List)
          .map((e) => PynqSitlStepResult.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
