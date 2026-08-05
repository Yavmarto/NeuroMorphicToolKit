// Data models for BrainChip Akida scaffold-export and runtime verification.
//
// Mirrors the Python backend schemas from:
// - neurocnl AkidaExportResult / AkidaSupportState
// - Neurochip Akida backend (akida_backend.py)
//
// Exportability and runtime verification are modeled separately:
// - NeuroCNL reports whether the network is unsupported or exportable as a
//   scaffold package plus mapped handoff payload.
// - Neurochip later verifies whether that mapped payload is actually
//   deployable via the Akida SDK in the current environment.

import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';

enum AkidaRuntimeMode {
  localSdk,
  remoteSdk,
  simulatorOnly,
  unknown;

  static AkidaRuntimeMode fromString(String? value) {
    switch (value) {
      case 'local_sdk':
        return AkidaRuntimeMode.localSdk;
      case 'remote_sdk':
      case 'remote_host':
        return AkidaRuntimeMode.remoteSdk;
      case 'simulator_only':
      case 'software_fallback':
        return AkidaRuntimeMode.simulatorOnly;
      default:
        return AkidaRuntimeMode.unknown;
    }
  }

  String get apiValue {
    switch (this) {
      case AkidaRuntimeMode.localSdk:
        return 'local_sdk';
      case AkidaRuntimeMode.remoteSdk:
        return 'remote_sdk';
      case AkidaRuntimeMode.simulatorOnly:
        return 'simulator_only';
      case AkidaRuntimeMode.unknown:
        return 'unknown';
    }
  }

  String get label {
    switch (this) {
      case AkidaRuntimeMode.localSdk:
        return 'Local SDK';
      case AkidaRuntimeMode.remoteSdk:
        return 'Remote SDK Host';
      case AkidaRuntimeMode.simulatorOnly:
        return 'Simulator Only';
      case AkidaRuntimeMode.unknown:
        return 'Unknown';
    }
  }
}

enum AkidaHostAuthMode {
  none,
  password,
  sshKey,
  basic,
  bearerToken;

  static AkidaHostAuthMode fromString(String? value) {
    switch (value) {
      case 'password':
        return AkidaHostAuthMode.password;
      case 'ssh_key':
        return AkidaHostAuthMode.sshKey;
      case 'basic':
        return AkidaHostAuthMode.basic;
      case 'bearer_token':
      case 'token':
        return AkidaHostAuthMode.bearerToken;
      case 'none':
      default:
        return AkidaHostAuthMode.none;
    }
  }

  String get apiValue {
    switch (this) {
      case AkidaHostAuthMode.none:
        return 'none';
      case AkidaHostAuthMode.password:
        return 'password';
      case AkidaHostAuthMode.sshKey:
        return 'ssh_key';
      case AkidaHostAuthMode.basic:
        return 'basic';
      case AkidaHostAuthMode.bearerToken:
        return 'bearer_token';
    }
  }
}

enum AkidaPairedHostState {
  unknown,
  unpaired,
  reachable,
  bootstrapping,
  installingRuntime,
  verifyingSdk,
  pending,
  ready,
  degraded,
  degradedOptionalCapability,
  simulatorOnly,
  blocked,
  preflightFailed,
  provisionFailed,
  error;

  static AkidaPairedHostState fromString(String? value) {
    switch (value) {
      case 'unpaired':
        return AkidaPairedHostState.unpaired;
      case 'reachable':
        return AkidaPairedHostState.reachable;
      case 'bootstrapping':
        return AkidaPairedHostState.bootstrapping;
      case 'installing_runtime':
        return AkidaPairedHostState.installingRuntime;
      case 'verifying_sdk':
        return AkidaPairedHostState.verifyingSdk;
      case 'pending':
        return AkidaPairedHostState.pending;
      case 'ready':
        return AkidaPairedHostState.ready;
      case 'degraded':
        return AkidaPairedHostState.degraded;
      case 'degraded_optional_capability':
        return AkidaPairedHostState.degradedOptionalCapability;
      case 'simulator_only':
        return AkidaPairedHostState.simulatorOnly;
      case 'blocked':
        return AkidaPairedHostState.blocked;
      case 'preflight_failed':
        return AkidaPairedHostState.preflightFailed;
      case 'provision_failed':
        return AkidaPairedHostState.provisionFailed;
      case 'error':
        return AkidaPairedHostState.error;
      case 'unknown':
      default:
        return AkidaPairedHostState.unknown;
    }
  }

  String get apiValue {
    switch (this) {
      case AkidaPairedHostState.unknown:
        return 'unknown';
      case AkidaPairedHostState.unpaired:
        return 'unpaired';
      case AkidaPairedHostState.reachable:
        return 'reachable';
      case AkidaPairedHostState.bootstrapping:
        return 'bootstrapping';
      case AkidaPairedHostState.installingRuntime:
        return 'installing_runtime';
      case AkidaPairedHostState.verifyingSdk:
        return 'verifying_sdk';
      case AkidaPairedHostState.pending:
        return 'pending';
      case AkidaPairedHostState.ready:
        return 'ready';
      case AkidaPairedHostState.degraded:
        return 'degraded';
      case AkidaPairedHostState.degradedOptionalCapability:
        return 'degraded_optional_capability';
      case AkidaPairedHostState.simulatorOnly:
        return 'simulator_only';
      case AkidaPairedHostState.blocked:
        return 'blocked';
      case AkidaPairedHostState.preflightFailed:
        return 'preflight_failed';
      case AkidaPairedHostState.provisionFailed:
        return 'provision_failed';
      case AkidaPairedHostState.error:
        return 'error';
    }
  }

  String get label {
    switch (this) {
      case AkidaPairedHostState.unknown:
        return 'Unknown';
      case AkidaPairedHostState.unpaired:
        return 'Host Added';
      case AkidaPairedHostState.reachable:
        return 'Connectivity Tested';
      case AkidaPairedHostState.bootstrapping:
        return 'Bootstrap In Progress';
      case AkidaPairedHostState.installingRuntime:
        return 'Neurochip Install In Progress';
      case AkidaPairedHostState.verifyingSdk:
        return 'SDK Verification In Progress';
      case AkidaPairedHostState.pending:
        return 'Pending';
      case AkidaPairedHostState.ready:
        return 'Ready';
      case AkidaPairedHostState.degraded:
        return 'Degraded';
      case AkidaPairedHostState.degradedOptionalCapability:
        return 'Degraded Optional Capability';
      case AkidaPairedHostState.simulatorOnly:
        return 'Simulator Only';
      case AkidaPairedHostState.blocked:
        return 'Blocked';
      case AkidaPairedHostState.preflightFailed:
        return 'Preflight Failed';
      case AkidaPairedHostState.provisionFailed:
        return 'Provision Failed';
      case AkidaPairedHostState.error:
        return 'Error';
    }
  }
}

/// Support state for BrainChip Akida target.
///
/// Export-time scaffold states come from NeuroCNL.
/// SDK states are retained for UI compatibility and may be used by runtime
/// surfaces that collapse export and verification into a single badge.
enum AkidaSupportState {
  /// All constraints met; scaffold package can be generated.
  exportableScaffold,

  /// Constraints met but near capacity thresholds or topology approximate.
  exportableScaffoldWithWarnings,

  /// One or more export-blocking rejections present.
  unsupported,

  /// Scaffold succeeded AND model mapped via Akida SDK.
  sdkDeployable,

  /// Scaffold OK but SDK unavailable or mapping failed.
  sdkNotDeployable;

  static AkidaSupportState fromString(String value) {
    switch (value) {
      case 'exportable_scaffold':
        return AkidaSupportState.exportableScaffold;
      case 'exportable_scaffold_with_warnings':
        return AkidaSupportState.exportableScaffoldWithWarnings;
      case 'unsupported':
        return AkidaSupportState.unsupported;
      case 'sdk_deployable':
        return AkidaSupportState.sdkDeployable;
      case 'sdk_not_deployable':
        return AkidaSupportState.sdkNotDeployable;
      default:
        return AkidaSupportState.unsupported;
    }
  }

  /// Human-readable label for UI display.
  String get label {
    switch (this) {
      case AkidaSupportState.exportableScaffold:
        return 'Exportable: scaffold package ready';
      case AkidaSupportState.exportableScaffoldWithWarnings:
        return 'Exportable: near capacity or approximate topology';
      case AkidaSupportState.unsupported:
        return 'Unsupported: see rejections';
      case AkidaSupportState.sdkDeployable:
        return 'Verified: Akida SDK runtime ready';
      case AkidaSupportState.sdkNotDeployable:
        return 'Scaffold Only: SDK verification blocked';
    }
  }

  /// Theme color for UI indicators, resolved from the suite's
  /// [NmtkShellTokens] semantic palette rather than a hardcoded hex value.
  ///
  /// Scaffold-only (no warnings) maps to [NmtkShellTokens.runningColor] —
  /// the "works, not yet fully verified" in-progress tier; warnings map to
  /// [NmtkShellTokens.warningColor]; unsupported/not-deployable map to
  /// [NmtkShellTokens.errorColor]; fully SDK-deployable maps to
  /// [NmtkShellTokens.healthyColor].
  Color colorFor(NmtkShellTokens tokens) {
    switch (this) {
      case AkidaSupportState.exportableScaffold:
        return tokens.runningColor;
      case AkidaSupportState.exportableScaffoldWithWarnings:
        return tokens.warningColor;
      case AkidaSupportState.unsupported:
        return tokens.errorColor;
      case AkidaSupportState.sdkDeployable:
        return tokens.healthyColor;
      case AkidaSupportState.sdkNotDeployable:
        return tokens.errorColor;
    }
  }

  /// Icon for UI indicators.
  IconData get icon {
    switch (this) {
      case AkidaSupportState.exportableScaffold:
        return Icons.architecture; // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      case AkidaSupportState.exportableScaffoldWithWarnings:
        return ZetaIcons.warning_outline;
      case AkidaSupportState.unsupported:
        return ZetaIcons.block;
      case AkidaSupportState.sdkDeployable:
        return ZetaIcons.check_circle;
      case AkidaSupportState.sdkNotDeployable:
        return ZetaIcons.cloud_off;
    }
  }
}

/// Response from the NeuroCNL Akida exportability endpoint.
class AkidaNetworkResponse {
  final AkidaSupportState supportState;
  final String akidaVersion;
  final String topologyVerdict;
  final List<String> warnings;
  final List<String> rejectionReasons;
  final Map<String, dynamic>? networkSummary;

  /// Pre-built mapped network for Neurochip /deploy/mapped.
  ///
  /// Null when [supportState] is [AkidaSupportState.unsupported] or when
  /// the topology is not faithful (e.g. recurrent / branching networks).
  final Map<String, dynamic>? mappedNetwork;

  const AkidaNetworkResponse({
    required this.supportState,
    required this.akidaVersion,
    required this.topologyVerdict,
    required this.warnings,
    required this.rejectionReasons,
    this.networkSummary,
    this.mappedNetwork,
  });

  factory AkidaNetworkResponse.fromJson(Map<String, dynamic> json) {
    return AkidaNetworkResponse(
      supportState: AkidaSupportState.fromString(
        json['support_state'] as String,
      ),
      akidaVersion: json['akida_version'] as String? ?? 'akida',
      topologyVerdict: json['topology_verdict'] as String? ?? 'unknown',
      warnings: (json['warnings'] as List).map((e) => e as String).toList(),
      rejectionReasons: (json['rejections'] as List)
          .map((e) => e as String)
          .toList(),
      networkSummary: json['network_summary'] as Map<String, dynamic>?,
      mappedNetwork: json['mapped_network'] as Map<String, dynamic>?,
    );
  }
}

// ---------------------------------------------------------------------------
// Runtime verification — reported by Neurochip verify/status endpoints
// ---------------------------------------------------------------------------

class AkidaEnvironmentChecks {
  final bool hostSupported;
  final bool pythonSupported;
  final bool tensorflowAvailable;
  final bool cnn2snnAvailable;
  final bool akidaModelsAvailable;
  final String recommendedRuntime;

  const AkidaEnvironmentChecks({
    required this.hostSupported,
    required this.pythonSupported,
    required this.tensorflowAvailable,
    required this.cnn2snnAvailable,
    required this.akidaModelsAvailable,
    required this.recommendedRuntime,
  });

  factory AkidaEnvironmentChecks.fromJson(Map<String, dynamic> json) {
    return AkidaEnvironmentChecks(
      hostSupported:
          json['hostSupported'] as bool? ??
          json['host_supported'] as bool? ??
          false,
      pythonSupported:
          json['pythonSupported'] as bool? ??
          json['python_supported'] as bool? ??
          false,
      tensorflowAvailable:
          json['tensorflowAvailable'] as bool? ??
          json['tensorflow_available'] as bool? ??
          false,
      cnn2snnAvailable:
          json['cnn2snnAvailable'] as bool? ??
          json['cnn2snn_available'] as bool? ??
          false,
      akidaModelsAvailable:
          json['akidaModelsAvailable'] as bool? ??
          json['akida_models_available'] as bool? ??
          false,
      recommendedRuntime:
          json['recommendedRuntime'] as String? ??
          json['recommended_runtime'] as String? ??
          'local_sdk',
    );
  }

  AkidaRuntimeMode get recommendedRuntimeMode =>
      AkidaRuntimeMode.fromString(recommendedRuntime);

  Map<String, dynamic> toJson() {
    return {
      'hostSupported': hostSupported,
      'pythonSupported': pythonSupported,
      'tensorflowAvailable': tensorflowAvailable,
      'cnn2snnAvailable': cnn2snnAvailable,
      'akidaModelsAvailable': akidaModelsAvailable,
      'recommendedRuntime': recommendedRuntime,
    };
  }
}

class AkidaSdkVerification {
  final bool sdkAvailable;
  final String sdkStatus;
  final List<String> sdkIssues;
  final String state;
  final Map<String, dynamic>? modelSummary;
  final String runtimeTarget;
  final String? deviceInfo;
  final String? sdkIssueDetail;
  final AkidaEnvironmentChecks? environmentChecks;

  const AkidaSdkVerification({
    required this.sdkAvailable,
    required this.sdkStatus,
    required this.sdkIssues,
    required this.state,
    this.modelSummary,
    this.runtimeTarget = 'unknown',
    this.deviceInfo,
    this.sdkIssueDetail,
    this.environmentChecks,
  });

  factory AkidaSdkVerification.fromJson(Map<String, dynamic> json) {
    return AkidaSdkVerification(
      sdkAvailable: json['sdk_available'] as bool? ?? false,
      sdkStatus: json['sdk_status'] as String? ?? 'unknown',
      sdkIssues:
          (json['sdk_issues'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      state: json['state'] as String? ?? 'unknown',
      modelSummary: json['model_summary'] as Map<String, dynamic>?,
      runtimeTarget: json['runtime_target'] as String? ?? 'unknown',
      deviceInfo: json['device_info'] as String?,
      sdkIssueDetail: json['sdk_issue_detail'] as String?,
      environmentChecks: json['environment_checks'] is Map<String, dynamic>
          ? AkidaEnvironmentChecks.fromJson(
              json['environment_checks'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  bool get isDeployable => sdkStatus == 'deployable';

  AkidaRuntimeMode get runtimeMode =>
      AkidaRuntimeMode.fromString(runtimeTarget);
}

class AkidaPairedHost {
  final String id;
  final String displayName;
  final String host;
  final int sshPort;
  final String username;
  final String runtimeApiUrl;
  final String controlApiUrl;
  final AkidaHostAuthMode authMode;
  final String credentialRef;
  final String password;
  final bool hasPassword;
  final String sshKeyPath;
  final String remoteInstallRoot;
  final String serviceUser;
  final String hostOs;
  final String pythonVersion;
  final AkidaRuntimeMode runtimeMode;
  final AkidaPairedHostState state;
  final String lastReadinessMessage;
  final String lastVerifiedAt;
  final bool isDefault;
  final AkidaEnvironmentChecks? capabilitySnapshot;
  final String installedRuntimeVersion;
  final String availableRuntimeVersion;
  final String runtimeArtifactSha256;
  final String runtimeUpdateState;
  final AkidaRuntimeUpdateJob? lastRuntimeUpdateJob;

  const AkidaPairedHost({
    required this.id,
    required this.displayName,
    required this.host,
    required this.sshPort,
    required this.username,
    required this.runtimeApiUrl,
    required this.controlApiUrl,
    required this.authMode,
    required this.credentialRef,
    required this.password,
    required this.hasPassword,
    required this.sshKeyPath,
    required this.remoteInstallRoot,
    required this.serviceUser,
    required this.hostOs,
    required this.pythonVersion,
    required this.runtimeMode,
    required this.state,
    required this.lastReadinessMessage,
    required this.lastVerifiedAt,
    this.isDefault = false,
    this.capabilitySnapshot,
    this.installedRuntimeVersion = '',
    this.availableRuntimeVersion = '',
    this.runtimeArtifactSha256 = '',
    this.runtimeUpdateState = '',
    this.lastRuntimeUpdateJob,
  });

  bool get isReady => state == AkidaPairedHostState.ready;

  bool get hasRuntimeUpdate =>
      availableRuntimeVersion.isNotEmpty &&
      installedRuntimeVersion != availableRuntimeVersion;

  factory AkidaPairedHost.fromJson(Map<String, dynamic> json) {
    return AkidaPairedHost(
      id: json['id'] as String? ?? '',
      displayName:
          json['displayName'] as String? ??
          json['display_name'] as String? ??
          'Akida Host',
      host: json['host'] as String? ?? '',
      sshPort: json['sshPort'] as int? ?? json['ssh_port'] as int? ?? 22,
      username: json['username'] as String? ?? json['user'] as String? ?? '',
      runtimeApiUrl:
          json['runtimeApiUrl'] as String? ??
          json['runtime_api_url'] as String? ??
          '',
      controlApiUrl:
          json['controlApiUrl'] as String? ??
          json['control_api_url'] as String? ??
          '',
      authMode: AkidaHostAuthMode.fromString(
        json['authMode'] as String? ?? json['auth_mode'] as String?,
      ),
      credentialRef:
          json['credentialRef'] as String? ??
          json['credential_ref'] as String? ??
          '',
      password: json['password'] as String? ?? '',
      hasPassword:
          json['hasPassword'] as bool? ??
          (json['password'] as String? ?? '').isNotEmpty,
      sshKeyPath:
          json['sshKeyPath'] as String? ??
          json['ssh_key_path'] as String? ??
          '',
      remoteInstallRoot:
          json['remoteInstallRoot'] as String? ??
          json['remote_install_root'] as String? ??
          '',
      serviceUser:
          json['serviceUser'] as String? ??
          json['service_user'] as String? ??
          '',
      hostOs: json['hostOs'] as String? ?? json['host_os'] as String? ?? '',
      pythonVersion:
          json['pythonVersion'] as String? ??
          json['python_version'] as String? ??
          '',
      runtimeMode: AkidaRuntimeMode.fromString(
        json['runtimeMode'] as String? ?? json['runtime_mode'] as String?,
      ),
      state: AkidaPairedHostState.fromString(json['state'] as String?),
      lastReadinessMessage:
          json['lastReadinessMessage'] as String? ??
          json['last_readiness_message'] as String? ??
          '',
      lastVerifiedAt:
          json['lastVerifiedAt'] as String? ??
          json['last_verified_at'] as String? ??
          '',
      isDefault: json['isDefault'] as bool? ?? false,
      capabilitySnapshot: json['capabilitySnapshot'] is Map<String, dynamic>
          ? AkidaEnvironmentChecks.fromJson(
              json['capabilitySnapshot'] as Map<String, dynamic>,
            )
          : json['capability_snapshot'] is Map<String, dynamic>
          ? AkidaEnvironmentChecks.fromJson(
              json['capability_snapshot'] as Map<String, dynamic>,
            )
          : null,
      installedRuntimeVersion: json['installedRuntimeVersion'] as String? ?? '',
      availableRuntimeVersion: json['availableRuntimeVersion'] as String? ?? '',
      runtimeArtifactSha256: json['runtimeArtifactSha256'] as String? ?? '',
      runtimeUpdateState: json['runtimeUpdateState'] as String? ?? '',
      lastRuntimeUpdateJob: json['lastRuntimeUpdateJob'] is Map<String, dynamic>
          ? AkidaRuntimeUpdateJob.fromJson(
              json['lastRuntimeUpdateJob'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'host': host,
      'sshPort': sshPort,
      'username': username,
      'runtimeApiUrl': runtimeApiUrl,
      'controlApiUrl': controlApiUrl,
      'authMode': authMode.apiValue,
      'credentialRef': credentialRef,
      'password': password,
      'hasPassword': hasPassword,
      'sshKeyPath': sshKeyPath,
      'remoteInstallRoot': remoteInstallRoot,
      'serviceUser': serviceUser,
      'hostOs': hostOs,
      'pythonVersion': pythonVersion,
      'runtimeMode': runtimeMode.apiValue,
      'state': state.apiValue,
      'lastReadinessMessage': lastReadinessMessage,
      'lastVerifiedAt': lastVerifiedAt,
      'isDefault': isDefault,
      if (capabilitySnapshot != null)
        'capabilitySnapshot': capabilitySnapshot!.toJson(),
      'installedRuntimeVersion': installedRuntimeVersion,
      'availableRuntimeVersion': availableRuntimeVersion,
      'runtimeArtifactSha256': runtimeArtifactSha256,
      'runtimeUpdateState': runtimeUpdateState,
      if (lastRuntimeUpdateJob != null)
        'lastRuntimeUpdateJob': lastRuntimeUpdateJob!.toJson(),
    };
  }

  AkidaPairedHost copyWith({
    String? id,
    String? displayName,
    String? host,
    int? sshPort,
    String? username,
    String? runtimeApiUrl,
    String? controlApiUrl,
    AkidaHostAuthMode? authMode,
    String? credentialRef,
    String? password,
    bool? hasPassword,
    String? sshKeyPath,
    String? remoteInstallRoot,
    String? serviceUser,
    String? hostOs,
    String? pythonVersion,
    AkidaRuntimeMode? runtimeMode,
    AkidaPairedHostState? state,
    String? lastReadinessMessage,
    String? lastVerifiedAt,
    bool? isDefault,
    AkidaEnvironmentChecks? capabilitySnapshot,
    String? installedRuntimeVersion,
    String? availableRuntimeVersion,
    String? runtimeArtifactSha256,
    String? runtimeUpdateState,
    AkidaRuntimeUpdateJob? lastRuntimeUpdateJob,
  }) {
    return AkidaPairedHost(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      host: host ?? this.host,
      sshPort: sshPort ?? this.sshPort,
      username: username ?? this.username,
      runtimeApiUrl: runtimeApiUrl ?? this.runtimeApiUrl,
      controlApiUrl: controlApiUrl ?? this.controlApiUrl,
      authMode: authMode ?? this.authMode,
      credentialRef: credentialRef ?? this.credentialRef,
      password: password ?? this.password,
      hasPassword: hasPassword ?? this.hasPassword,
      sshKeyPath: sshKeyPath ?? this.sshKeyPath,
      remoteInstallRoot: remoteInstallRoot ?? this.remoteInstallRoot,
      serviceUser: serviceUser ?? this.serviceUser,
      hostOs: hostOs ?? this.hostOs,
      pythonVersion: pythonVersion ?? this.pythonVersion,
      runtimeMode: runtimeMode ?? this.runtimeMode,
      state: state ?? this.state,
      lastReadinessMessage: lastReadinessMessage ?? this.lastReadinessMessage,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
      isDefault: isDefault ?? this.isDefault,
      capabilitySnapshot: capabilitySnapshot ?? this.capabilitySnapshot,
      installedRuntimeVersion:
          installedRuntimeVersion ?? this.installedRuntimeVersion,
      availableRuntimeVersion:
          availableRuntimeVersion ?? this.availableRuntimeVersion,
      runtimeArtifactSha256:
          runtimeArtifactSha256 ?? this.runtimeArtifactSha256,
      runtimeUpdateState: runtimeUpdateState ?? this.runtimeUpdateState,
      lastRuntimeUpdateJob: lastRuntimeUpdateJob ?? this.lastRuntimeUpdateJob,
    );
  }
}

/// Persisted launcher job for installing the release-matched Neurochip wheel.
class AkidaRuntimeUpdateJob {
  const AkidaRuntimeUpdateJob({
    required this.jobId,
    required this.hostId,
    required this.artifactVersion,
    required this.artifactSha256,
    required this.stage,
    required this.progress,
    required this.message,
    required this.status,
    this.errorCode = '',
    this.recovery = '',
    this.installedVersion = '',
    this.installMode = '',
    this.rolledBack = false,
  });

  final String jobId;
  final String hostId;
  final String artifactVersion;
  final String artifactSha256;
  final String stage;
  final int progress;
  final String message;
  final String status;
  final String errorCode;
  final String recovery;
  final String installedVersion;
  final String installMode;
  final bool rolledBack;

  bool get isTerminal => status == 'completed' || status == 'failed';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';

  factory AkidaRuntimeUpdateJob.fromJson(Map<String, dynamic> json) {
    return AkidaRuntimeUpdateJob(
      jobId: json['jobId'] as String? ?? '',
      hostId: json['hostId'] as String? ?? '',
      artifactVersion: json['artifactVersion'] as String? ?? '',
      artifactSha256: json['artifactSha256'] as String? ?? '',
      stage: json['stage'] as String? ?? 'queued',
      progress: (json['progress'] as num?)?.round() ?? 0,
      message: json['message'] as String? ?? '',
      status: json['status'] as String? ?? 'queued',
      errorCode: json['errorCode'] as String? ?? '',
      recovery: json['recovery'] as String? ?? '',
      installedVersion: json['installedVersion'] as String? ?? '',
      installMode: json['installMode'] as String? ?? '',
      rolledBack: json['rolledBack'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'jobId': jobId,
    'hostId': hostId,
    'artifactVersion': artifactVersion,
    'artifactSha256': artifactSha256,
    'stage': stage,
    'progress': progress,
    'message': message,
    'status': status,
    'errorCode': errorCode,
    'recovery': recovery,
    'installedVersion': installedVersion,
    'installMode': installMode,
    'rolledBack': rolledBack,
  };
}

// ---------------------------------------------------------------------------
// Deploy job status — mirrors Akida backend lifecycle
// ---------------------------------------------------------------------------

/// Lifecycle state of an Akida SDK deploy job.
///
/// Maps to the backend's deployment pipeline states:
///   not_initialised → [notInitialised]
///   sdk_loading     → [sdkLoading]
///   model_mapping   → [modelMapping]
///   mapped          → [mapped]
///   running         → [running]
///   failed          → [failed]
enum AkidaDeployJobStatus {
  /// No deploy has been attempted yet.
  notInitialised,

  /// Akida SDK is being loaded and initialised.
  sdkLoading,

  /// Model is being mapped to Akida device/simulator.
  modelMapping,

  /// Model successfully mapped and ready to run.
  mapped,

  /// Model is actively running inference.
  running,

  /// Deploy or inference failed.
  failed;

  static AkidaDeployJobStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'not_initialised':
      case 'not_initialized':
        return AkidaDeployJobStatus.notInitialised;
      case 'sdk_loading':
        return AkidaDeployJobStatus.sdkLoading;
      case 'model_mapping':
        return AkidaDeployJobStatus.modelMapping;
      // 'constructed' means the model is built but SDK mapping failed or was
      // skipped (scaffold-only path). Treat as terminal mapped state so the
      // poll timer stops and the UI shows the package as ready.
      case 'constructed':
        return AkidaDeployJobStatus.mapped;
      case 'mapped':
        return AkidaDeployJobStatus.mapped;
      case 'running':
        return AkidaDeployJobStatus.running;
      case 'failed':
        return AkidaDeployJobStatus.failed;
      default:
        return AkidaDeployJobStatus.notInitialised;
    }
  }

  double get progressFraction {
    switch (this) {
      case AkidaDeployJobStatus.notInitialised:
        return 0.0;
      case AkidaDeployJobStatus.sdkLoading:
        return 0.25;
      case AkidaDeployJobStatus.modelMapping:
        return 0.5;
      case AkidaDeployJobStatus.mapped:
        return 1.0;
      case AkidaDeployJobStatus.running:
        return 0.9;
      case AkidaDeployJobStatus.failed:
        return 0.0;
    }
  }
}

/// Deploy status snapshot from Akida backend.
class AkidaDeployJob {
  final AkidaDeployJobStatus status;
  final String? deviceInfo;

  const AkidaDeployJob({required this.status, this.deviceInfo});

  factory AkidaDeployJob.fromJson(Map<String, dynamic> json) {
    return AkidaDeployJob(
      status: AkidaDeployJobStatus.fromString(json['state'] as String),
      deviceInfo: json['device_info'] as String?,
    );
  }

  factory AkidaDeployJob.fromVerification(AkidaSdkVerification verification) {
    return AkidaDeployJob(
      status: AkidaDeployJobStatus.fromString(verification.state),
      deviceInfo: verification.deviceInfo,
    );
  }
}
