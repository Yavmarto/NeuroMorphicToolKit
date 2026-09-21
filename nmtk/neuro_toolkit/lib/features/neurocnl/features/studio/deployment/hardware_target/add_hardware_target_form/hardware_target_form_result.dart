import 'package:neuro_toolkit/features/neurocnl/models/sc_neurocore_synthesis_target.dart';

class HardwareTargetFormResult {
  const HardwareTargetFormResult({
    required this.editingEntryId,
    required this.displayName,
    required this.host,
    required this.username,
    required this.sshPort,
    required this.authMode,
    required this.credentialRef,
    required this.password,
    required this.sshKeyPath,
    required this.runtimeApiUrlOverride,
    required this.overlayVersion,
    required this.runtimeApiUrl,
    required this.controlApiUrl,
    required this.remoteInstallRoot,
    required this.serviceUser,
    required this.isDefault,
    this.sameHostAsBackend = false,
    // SC-NeuroCore FPGA synthesis fields (only populated when
    // targetType == 'sc_neurocore_fpga').
    this.scFamily = ScNeuroCoreFamily.ice40,
    this.scToolchain = ScNeuroCoreToolchain.yosysNextpnr,
    this.scDeviceSpec = '',
    this.scDeploymentMode = ScNeuroCoreDeploymentMode.local,
    this.scHost = '',
    this.scSshPort = 22,
    this.scUsername = '',
    this.scSshKeyPath = '',
    this.scToolchainBinPath = '',
    this.scOutputDirectory = '',
    this.deviceIdentifier = '',
  });

  final String? editingEntryId;
  final String displayName;
  final String host;
  final String username;
  final int sshPort;
  final String authMode;
  final String credentialRef;

  /// `null` keeps the saved password, `''` clears it, anything else sets it.
  /// See `_AddHardwareTargetFormState._submittedPassword`.
  final String? password;
  final String sshKeyPath;
  final String runtimeApiUrlOverride;
  final String overlayVersion;
  final String runtimeApiUrl;
  final String controlApiUrl;
  final String remoteInstallRoot;
  final String serviceUser;
  final bool isDefault;

  /// Only meaningful for the `akida` target type — see the checkbox in the
  /// akida section of `_buildTypeSpecificForm`.
  final bool sameHostAsBackend;
  // SC-NeuroCore FPGA synthesis fields.
  final ScNeuroCoreFamily scFamily;
  final ScNeuroCoreToolchain scToolchain;
  final String scDeviceSpec;
  final ScNeuroCoreDeploymentMode scDeploymentMode;
  final String scHost;
  final int scSshPort;
  final String scUsername;
  final String scSshKeyPath;
  final String scToolchainBinPath;
  final String scOutputDirectory;

  /// USB serial / stable id for same-host Speck devices.
  final String deviceIdentifier;
}
