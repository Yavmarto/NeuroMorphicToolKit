import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/models/sc_neurocore_synthesis_target.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/server_config_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/sc_neurocore_toolchain_check_service.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/studio_shared.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/hardware_target/hardware_target_dialog/saved_hardware_target_entry.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/hardware_target/add_hardware_target_form/auth_credential_section.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/hardware_target/add_hardware_target_form/hardware_target_form_result.dart';

class AddHardwareTargetForm extends ConsumerStatefulWidget {
  const AddHardwareTargetForm({
    super.key,
    required this.targetType,
    required this.initialEntry,
    required this.errorMessage,
    required this.isSaving,
    required this.onCancel,
    required this.onSave,
    this.statusMessage,
    this.onSaveAndTest,
  });

  final String targetType;
  final SavedHardwareTargetEntry? initialEntry;
  final String? errorMessage;

  /// Result of the last connectivity test, shown under the form.
  final String? statusMessage;
  final bool isSaving;
  final VoidCallback onCancel;
  final Future<void> Function(HardwareTargetFormResult form) onSave;

  /// Saves, then runs the host's connectivity test and reports the result.
  ///
  /// Separate from [onSave] because the test route is keyed by host id: a host
  /// being created has no id yet, so testing before saving is impossible.
  /// Combining them means a brand-new host is verifiable without a second trip
  /// through the dialog.
  final Future<void> Function(HardwareTargetFormResult form)? onSaveAndTest;

  @override
  ConsumerState<AddHardwareTargetForm> createState() =>
      _AddHardwareTargetFormState();
}

class _AddHardwareTargetFormState extends ConsumerState<AddHardwareTargetForm> {
  static const String _savedPasswordMask = '********';
  static const int _akidaRuntimePort = int.fromEnvironment(
    'NMTK_AKIDA_RUNTIME_PORT',
    defaultValue: 8002,
  );
  static const int _akidaControlPort = int.fromEnvironment(
    'NMTK_AKIDA_CONTROL_PORT',
    defaultValue: 8091,
  );

  /// Port the board-side agent listens on; matches
  /// `PynqLauncherRuntimeContract.runtime_port`. Shown in helper text only —
  /// launcher control derives the URL itself unless the user overrides it.
  static const int _pynqRuntimePort = int.fromEnvironment(
    'NMTK_PYNQ_RUNTIME_PORT',
    defaultValue: 8002,
  );

  /// The user the PYNQ SD-card image ships with.
  static const String _pynqDefaultUsername = 'xilinx';

  late final TextEditingController _displayNameController;
  late final TextEditingController _hostController;
  late final TextEditingController _usernameController;
  late final TextEditingController _sshPortController;
  late final TextEditingController _credentialRefController;
  late final TextEditingController _passwordController;
  late final TextEditingController _sshKeyPathController;
  late final TextEditingController _runtimeApiUrlOverrideController;
  late final TextEditingController _overlayVersionController;
  late final TextEditingController _runtimeApiUrlController;
  late final TextEditingController _controlApiUrlController;
  late final TextEditingController _remoteInstallRootController;
  late final TextEditingController _serviceUserController;
  // SC-NeuroCore FPGA synthesis target fields.
  late final TextEditingController _deviceSpecController;
  late final TextEditingController _toolchainBinPathController;
  late final TextEditingController _outputDirectoryController;
  ScNeuroCoreFamily _scFamily = ScNeuroCoreFamily.ice40;
  ScNeuroCoreToolchain _scToolchain = ScNeuroCoreToolchain.yosysNextpnr;
  ScNeuroCoreDeploymentMode _scDeploymentMode = ScNeuroCoreDeploymentMode.local;
  String _authMode = 'password';
  bool _akidaHasSavedPassword = false;
  bool _pynqHasSavedPassword = false;
  bool _isDefault = false;
  bool _sameHostAsBackend = false;

  /// Stops auto-detection once the user (or a saved record) has had a say.
  ///
  /// Same intent as [_lastDerivedHost] for the URL fields: derive a sensible
  /// default, then never fight an explicit choice.
  bool _sameHostAsBackendTouched = false;
  bool _showAkidaAdvancedSettings = false;
  bool _showPynqAdvancedSettings = false;

  /// Tracks the host value that was last used to auto-derive the Akida runtime
  /// and control API URLs, so we only overwrite the fields while they still
  /// contain the auto-derived value (i.e. the user hasn't manually edited them).
  String _lastDerivedHost = '';

  /// Drives the service-account warning under the SSH user field.
  ///
  /// This is deliberately a notifier rather than a `setState` flag.
  /// `ZetaTextInput` derives its `initialValue` from `controller.text` at
  /// construction time, so on every rebuild its `didUpdateWidget` writes the
  /// controller's text back into the controller — and that write dispatches
  /// this widget's controller listeners *during the build phase*, where
  /// `setState` throws "setState() or markNeedsBuild() called during build".
  /// Rebuilding only this one notifier's listener keeps the text fields out of
  /// the rebuild entirely, which also stops that write-back from clearing the
  /// caret mid-word.
  final ValueNotifier<bool> _usernameIsServiceAccount = ValueNotifier<bool>(
    false,
  );

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _hostController = TextEditingController();
    _usernameController = TextEditingController();
    _sshPortController = TextEditingController(text: '22');
    _credentialRefController = TextEditingController();
    _passwordController = TextEditingController();
    _sshKeyPathController = TextEditingController();
    _runtimeApiUrlOverrideController = TextEditingController();
    _overlayVersionController = TextEditingController();
    _runtimeApiUrlController = TextEditingController();
    _controlApiUrlController = TextEditingController();
    _remoteInstallRootController = TextEditingController();
    _serviceUserController = TextEditingController(text: 'neurochip');
    _deviceSpecController = TextEditingController();
    _toolchainBinPathController = TextEditingController();
    _outputDirectoryController = TextEditingController();

    // Auto-derive Akida runtime/control API URLs from the host address so the
    // user does not have to type them manually for typical setups.
    if (widget.targetType == 'akida') {
      _hostController.addListener(_onAkidaHostChanged);
      // Drives the service-account warning below the SSH user field, which has
      // to react as the user types rather than only on save. The service-user
      // field feeds the same comparison, so editing it under Advanced settings
      // has to re-evaluate the warning too.
      _usernameController.addListener(_onAkidaUsernameChanged);
      _serviceUserController.addListener(_onAkidaUsernameChanged);
    }

    if (widget.targetType == 'pynq') {
      _usernameController.text = _pynqDefaultUsername;
    }

    switch (widget.initialEntry?.targetData) {
      case final PynqPairedBoard board:
        _displayNameController.text = board.displayName;
        _hostController.text = board.host;
        _usernameController.text = board.username;
        _sshPortController.text = board.sshPort.toString();
        _runtimeApiUrlOverrideController.text = board.runtimeApiUrlOverride;
        _overlayVersionController.text = board.overlayVersion;
        _authMode = board.authMode.apiValue;
        _sshKeyPathController.text = board.sshKeyPath;
        _pynqHasSavedPassword = board.hasPassword;
        if (_pynqHasSavedPassword && _authMode == 'password') {
          _passwordController.text = _savedPasswordMask;
        }
        _isDefault = board.isDefault;
      case final AkidaPairedHost host:
        _displayNameController.text = host.displayName;
        _hostController.text = host.host;
        _usernameController.text = host.username;
        _sshPortController.text = host.sshPort.toString();
        _runtimeApiUrlController.text = host.runtimeApiUrl;
        _controlApiUrlController.text = host.controlApiUrl;
        _remoteInstallRootController.text = host.remoteInstallRoot;
        _serviceUserController.text = host.serviceUser;
        _authMode = host.authMode.apiValue;
        _sshKeyPathController.text = host.sshKeyPath;
        _akidaHasSavedPassword = host.hasPassword;
        if (_akidaHasSavedPassword && _authMode == 'password') {
          _passwordController.text = _savedPasswordMask;
        }
        _isDefault = host.isDefault;
        _sameHostAsBackend = host.sameHostAsBackend;
        // A saved record already carries the user's answer, so detection must
        // not overwrite it when the pre-filled host fires the listener below.
        _sameHostAsBackendTouched = true;
      case final ScNeuroCoreTarget scTarget:
        _displayNameController.text = scTarget.displayName;
        _scFamily = scTarget.family;
        _deviceSpecController.text = scTarget.deviceSpec;
        _scToolchain = scTarget.toolchain;
        _scDeploymentMode = scTarget.deploymentMode;
        _hostController.text = scTarget.host;
        _sshPortController.text = scTarget.sshPort.toString();
        _usernameController.text = scTarget.username;
        _sshKeyPathController.text = scTarget.sshKeyPath;
        _toolchainBinPathController.text = scTarget.toolchainBinPath;
        _outputDirectoryController.text = scTarget.outputDirectory;
        _isDefault = scTarget.isDefault;
      case _:
        break;
    }

    _usernameIsServiceAccount.value = _usernameLooksLikeServiceAccount;
  }

  /// Auto-populates the Neurochip runtime URL (port 8002) and control API URL
  /// (port 8091) whenever the host address changes — but only while those
  /// fields still contain the previously auto-derived value (meaning the user
  /// has not manually overridden them).
  ///
  /// Deferred to after the frame for the same reason as
  /// [_usernameIsServiceAccount]: this listener can fire from inside
  /// `ZetaTextInput.didUpdateWidget` while a build is in progress, and writing
  /// to another field's controller there makes *that* field call `setState`
  /// during build, which throws.
  void _onAkidaHostChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _deriveAkidaUrlsFromHost();
      _syncSameHostAsBackend();
    });
  }

  /// The host part of the backend this app is talking to, or null if unknown.
  String? _backendHostAddress() {
    final host = ref.read(serverConfigProvider).backendUri.host.trim();
    return host.isEmpty ? null : host.toLowerCase();
  }

  /// Ticks the same-machine box when the Akida address *is* the backend server.
  ///
  /// A card in the machine that already runs the backend has to be reached
  /// through the container gateway rather than over the network, and an end
  /// user has no way to know that — so the app works it out instead of relying
  /// on the box being found and understood.
  ///
  /// Runs only from the post-frame callback in [_onAkidaHostChanged]: this
  /// calls `setState`, and a controller listener firing during Zeta's
  /// build-phase write-back would otherwise throw. The early return on an
  /// unchanged value also stops setState -> rebuild -> write-back -> listener
  /// from cycling.
  void _syncSameHostAsBackend() {
    if (_sameHostAsBackendTouched) return;
    final typed = _hostController.text.trim().toLowerCase();
    if (typed.isEmpty) return;
    final backendHost = _backendHostAddress();
    final matches = backendHost != null && backendHost == typed;
    if (matches == _sameHostAsBackend) return;
    setState(() {
      _sameHostAsBackend = matches;
    });
  }

  void _deriveAkidaUrlsFromHost() {
    final host = _hostController.text.trim();
    if (host.isEmpty) return;

    final prevRuntime = _lastDerivedHost.isEmpty
        ? ''
        : 'http://$_lastDerivedHost:$_akidaRuntimePort';
    final prevControl = _lastDerivedHost.isEmpty
        ? ''
        : 'http://$_lastDerivedHost:$_akidaControlPort';

    if (_runtimeApiUrlController.text == prevRuntime) {
      _runtimeApiUrlController.text = 'http://$host:$_akidaRuntimePort';
    }
    if (_controlApiUrlController.text == prevControl) {
      _controlApiUrlController.text = 'http://$host:$_akidaControlPort';
    }
    _lastDerivedHost = host;
  }

  void _onAkidaUsernameChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _usernameIsServiceAccount.value = _usernameLooksLikeServiceAccount;
    });
  }

  @override
  void dispose() {
    if (widget.targetType == 'akida') {
      _hostController.removeListener(_onAkidaHostChanged);
      _usernameController.removeListener(_onAkidaUsernameChanged);
      _serviceUserController.removeListener(_onAkidaUsernameChanged);
    }
    _usernameIsServiceAccount.dispose();
    _displayNameController.dispose();
    _hostController.dispose();
    _usernameController.dispose();
    _sshPortController.dispose();
    _credentialRefController.dispose();
    _passwordController.dispose();
    _sshKeyPathController.dispose();
    _runtimeApiUrlOverrideController.dispose();
    _overlayVersionController.dispose();
    _runtimeApiUrlController.dispose();
    _controlApiUrlController.dispose();
    _remoteInstallRootController.dispose();
    _serviceUserController.dispose();
    _deviceSpecController.dispose();
    _toolchainBinPathController.dispose();
    _outputDirectoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // No card/border wrapper here: this form already renders inside
        // HardwareTargetDialog's dialog surface, so a second bordered,
        // coloured container around the fields would be a card nested
        // inside a card.
        Flexible(
          child: SingleChildScrollView(child: _buildTypeSpecificForm(context)),
        ),
        if (widget.errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            widget.errorMessage!,
            style: Zeta.of(
              context,
            ).textStyles.bodyXSmall.copyWith(color: AppTheme.error),
          ),
        ],
        if (widget.statusMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            widget.statusMessage!,
            key: const Key('hardware-target-form-status'),
            style: Zeta.of(
              context,
            ).textStyles.bodyXSmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
        const SizedBox(height: 12),
        // Wrap, not Row: three actions plus "Save and test connection" overflow
        // the 560px dialog at its narrowest.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            // Never gated on isSaving: this is the only affordance that lets
            // the user leave the dialog while a save is in flight — the
            // dialog has no cancel/close button of its own while the form is
            // showing, so disabling this one would strand the user in the
            // loading state with no working back/cancel affordance.
            ZetaButton.text(onPressed: widget.onCancel, label: 'Cancel'),
            if (widget.onSaveAndTest != null)
              ZetaButton.outline(
                key: const Key('hardware-target-save-and-test'),
                onPressed: widget.isSaving
                    ? null
                    : () => widget.onSaveAndTest!(_buildFormResult()),
                label: widget.isSaving
                    ? 'Working…'
                    : 'Save and test connection',
              ),
            ZetaButton(
              onPressed: widget.isSaving ? null : _handleSave,
              label: widget.isSaving ? 'Saving...' : 'Save',
            ),
          ],
        ),
      ],
    );
  }

  /// A checkbox rendered directly on the dialog surface (no card wrapper).
  ///
  /// The [ListTile] a [CheckboxListTile] builds paints its ink on the nearest
  /// ancestor [Material], which may sit above an opaque ancestor and hide the
  /// ripple; current stable Flutter also trips a debug assertion over it.
  /// Wrapping the tile in its own transparent [Material] is the
  /// framework-recommended fix and leaves the look unchanged.
  Widget _formCheckboxTile({
    Key? key,
    required String title,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Material(
      type: MaterialType.transparency,
      child: CheckboxListTile(
        key: key,
        title: Text(title),
        value: value,
        onChanged: onChanged,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildTypeSpecificForm(BuildContext context) {
    return switch (widget.targetType) {
      'akida' => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StudioFormField(
            controller: _displayNameController,
            label: 'Display name',
          ),
          const SizedBox(height: 12),
          // A card that lives in the machine already running the backend needs
          // no separate connection details: the app already reaches that server,
          // so checking the box collapses the form to a name-only entry.
          _formCheckboxTile(
            key: const Key('akida-same-host-as-backend-checkbox'),
            title: 'This is the same machine as your backend server',
            value: _sameHostAsBackend,
            onChanged: (value) {
              setState(() {
                _sameHostAsBackend = value ?? false;
                // An explicit choice outranks detection from here on.
                _sameHostAsBackendTouched = true;
              });
            },
          ),
          // The card's connection details are hidden (not removed) once the box
          // is checked: Zeta text inputs bind an external controller in
          // `initState` and never release the listener, so unmounting a field
          // mid-dialog and re-adding it later makes the disposed instance call
          // `setState` on the next keystroke. `Offstage` collapses the section
          // without that dispose/re-add cycle.
          Offstage(
            offstage: _sameHostAsBackend,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                StudioFormField(
                  controller: _hostController,
                  label: 'Host address',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: StudioFormField(
                        controller: _usernameController,
                        label: 'SSH user',
                        helperText:
                            'Your own login on the host — the one that can sudo. '
                            'Not the service account.',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StudioFormField(
                        controller: _sshPortController,
                        label: 'SSH port',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                // The service account is created with `--shell /usr/sbin/nologin`
                // and no password, so SSH as that name can never authenticate.
                // Entering it here is an easy mistake — it is the default of the
                // *service account* field in Advanced settings, and the two read as
                // interchangeable. Warn rather than block: a host provisioned
                // outside this app could legitimately have a real login by that
                // name.
                ValueListenableBuilder<bool>(
                  valueListenable: _usernameIsServiceAccount,
                  builder: (context, isServiceAccount, _) {
                    if (!isServiceAccount) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '"${_usernameController.text.trim()}" is the service '
                        'account this app creates on the host. It has no password '
                        'and no login shell, so SSH with it always fails. Use your '
                        'own account here; the service account is set under '
                        'Advanced settings.',
                        key: const Key(
                          'akida-service-account-as-ssh-user-warning',
                        ),
                        style: Zeta.of(context).textStyles.bodyXSmall.copyWith(
                          color: NmtkShellTokens.of(context).degradedColor,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                AuthCredentialSection(
                  authMode: _authMode,
                  onAuthModeChanged: (value) =>
                      setState(() => _authMode = value),
                  passwordController: _passwordController,
                  sshKeyPathController: _sshKeyPathController,
                  hasSavedPassword: _akidaHasSavedPassword,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ZetaButton.text(
                    key: const Key('akida-advanced-settings-toggle'),
                    onPressed: () => setState(
                      () => _showAkidaAdvancedSettings =
                          !_showAkidaAdvancedSettings,
                    ),
                    label: _showAkidaAdvancedSettings
                        ? 'Hide advanced settings'
                        : 'Advanced settings',
                  ),
                ),
                if (_showAkidaAdvancedSettings) ...[
                  const SizedBox(height: 12),
                  StudioFormField(
                    controller: _runtimeApiUrlController,
                    label: 'Neurochip runtime URL',
                    helperText: 'Derived automatically from the host address',
                  ),
                  const SizedBox(height: 12),
                  StudioFormField(
                    controller: _controlApiUrlController,
                    label: 'Control API URL',
                  ),
                  const SizedBox(height: 12),
                  StudioFormField(
                    controller: _remoteInstallRootController,
                    label: 'Remote install root',
                    helperText:
                        'Leave blank to use the backend release default',
                  ),
                  const SizedBox(height: 12),
                  StudioFormField(
                    controller: _serviceUserController,
                    label: 'Target service user',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _formCheckboxTile(
            title: 'Set as default target',
            value: _isDefault,
            onChanged: (value) {
              setState(() => _isDefault = value ?? false);
            },
          ),
        ],
      ),
      'pynq' => _buildPynqForm(),
      'sc_neurocore_fpga' => _buildScNeuroCoreForm(),
      // ignore: no_default_cases
      _ => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StudioFormField(
            controller: _displayNameController,
            label: 'Display name',
          ),
        ],
      ),
    };
  }

  /// Pairing form for a PYNQ-Z2 board.
  ///
  /// Shorter than the Akida form on purpose, because the board asks less of the
  /// user: everything the launcher needs beyond SSH is derived from the address
  /// (runtime port 8002) or fixed by the overlay contract. In particular there
  /// is no same-machine checkbox — a PYNQ-Z2 is always a separate board — no
  /// service-account field, and no overlay file to choose, since the overlay
  /// ships with the backend.
  Widget _buildPynqForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StudioFormField(
          controller: _displayNameController,
          label: 'Display name',
          helperText: 'e.g. Bench PYNQ-Z2',
        ),
        const SizedBox(height: 12),
        StudioFormField(
          controller: _hostController,
          label: 'Board address',
          helperText:
              'The address the board booted with — e.g. 192.168.2.99 or '
              'pynq.local. Find it on the PYNQ image\'s own start page.',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StudioFormField(
                controller: _usernameController,
                label: 'SSH user',
                helperText:
                    'The PYNQ image ships with "xilinx", which can sudo.',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StudioFormField(
                controller: _sshPortController,
                label: 'SSH port',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AuthCredentialSection(
          authMode: _authMode,
          onAuthModeChanged: (value) => setState(() => _authMode = value),
          passwordController: _passwordController,
          sshKeyPathController: _sshKeyPathController,
          hasSavedPassword: _pynqHasSavedPassword,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: ZetaButton.text(
            key: const Key('pynq-advanced-settings-toggle'),
            onPressed: () => setState(
              () => _showPynqAdvancedSettings = !_showPynqAdvancedSettings,
            ),
            label: _showPynqAdvancedSettings
                ? 'Hide advanced settings'
                : 'Advanced settings',
          ),
        ),
        if (_showPynqAdvancedSettings) ...[
          const SizedBox(height: 12),
          StudioFormField(
            controller: _runtimeApiUrlOverrideController,
            label: 'Board runtime URL override',
            helperText:
                'Leave blank to use http://<board address>:$_pynqRuntimePort.',
          ),
        ],
        const SizedBox(height: 12),
        _formCheckboxTile(
          key: const Key('pynq-default-target-checkbox'),
          title: 'Set as default target',
          value: _isDefault,
          onChanged: (value) {
            setState(() => _isDefault = value ?? false);
          },
        ),
      ],
    );
  }

  /// Synthesis target form for SC-NeuroCore FPGA RTL.
  ///
  /// Fields: display name, FPGA family (dropdown), device spec, toolchain
  /// (dropdown — filtered by family), optional toolchain binary path, optional
  /// output directory, default checkbox.  No SSH or overlay-version fields.
  Widget _buildScNeuroCoreForm() {
    final compatibleToolchains = ScNeuroCoreToolchain.compatibleWith(_scFamily);
    // Guard: ensure _scToolchain stays compatible when family changes.
    if (!compatibleToolchains.contains(_scToolchain)) {
      _scToolchain = compatibleToolchains.first;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StudioFormField(
          controller: _displayNameController,
          label: 'Display name',
          helperText: 'e.g. iCE40 HX8K dev board',
        ),
        const SizedBox(height: 12),
        // FPGA family dropdown.
        Text(
          'FPGA family',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 6),
        ZetaDropdown<ScNeuroCoreFamily>(
          key: const Key('sc-neurocore-family-dropdown'),
          value: _scFamily,
          items: [
            for (final family in ScNeuroCoreFamily.values)
              ZetaDropdownItem<ScNeuroCoreFamily>(
                value: family,
                label: family.label,
                icon: Icon(
                  family.icon,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
          onChange: (item) => setState(() {
            _scFamily = item.value;
            final compatible = ScNeuroCoreToolchain.compatibleWith(_scFamily);
            if (!compatible.contains(_scToolchain)) {
              _scToolchain = compatible.first;
            }
          }),
        ),
        const SizedBox(height: 12),
        StudioFormField(
          controller: _deviceSpecController,
          label: 'FPGA Part Number (Device Spec)',
          helperText:
              'The exact vendor part number passed to the synthesis compiler (e.g. xc7z020clg400-1). Required for bitstream generation.',
        ),
        const SizedBox(height: 12),
        // Toolchain dropdown (filtered by family).
        Text(
          'Toolchain',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 6),
        ZetaDropdown<ScNeuroCoreToolchain>(
          key: const Key('sc-neurocore-toolchain-dropdown'),
          value: _scToolchain,
          items: [
            for (final tc in compatibleToolchains)
              ZetaDropdownItem<ScNeuroCoreToolchain>(
                value: tc,
                label: tc.label,
              ),
          ],
          onChange: (item) => setState(() => _scToolchain = item.value),
        ),
        const SizedBox(height: 12),
        StudioFormField(
          controller: _toolchainBinPathController,
          label: 'Toolchain binary path (on server)',
          helperText:
              'Absolute path on the server running CNL Studio. Leave blank to use the server\'s \$PATH.',
        ),
        const SizedBox(height: 12),
        // Label above the control, not beside it — matching the FPGA family
        // and toolchain dropdowns above. A side-by-side Row here does not
        // wrap, so at the minimum supported mobile width the label and the
        // two-segment control could not both fit on one line.
        Text(
          'Deployment mode',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 6),
        ZetaSegmentedControl<ScNeuroCoreDeploymentMode>(
          selected: _scDeploymentMode,
          onChanged: (mode) => setState(() => _scDeploymentMode = mode),
          segments: const [
            ZetaButtonSegment<ScNeuroCoreDeploymentMode>(
              value: ScNeuroCoreDeploymentMode.local,
              child: Text('Local File'),
            ),
            ZetaButtonSegment<ScNeuroCoreDeploymentMode>(
              value: ScNeuroCoreDeploymentMode.network,
              child: Text('Network (SSH)'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_scDeploymentMode == ScNeuroCoreDeploymentMode.network) ...[
          StudioFormField(
            controller: _hostController,
            label: 'Host address',
            helperText: 'e.g. 192.168.1.100 or pynq.local',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: StudioFormField(
                  controller: _usernameController,
                  label: 'Username',
                  helperText: 'e.g. xilinx',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StudioFormField(
                  controller: _sshPortController,
                  label: 'SSH Port',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StudioFormField(
            controller: _sshKeyPathController,
            label: 'SSH key path',
            helperText:
                'Absolute path to the private key file on this machine.',
          ),
        ] else ...[
          StudioFormField(
            controller: _outputDirectoryController,
            label: 'Output directory (optional)',
            helperText:
                'Directory for generated RTL and bitstream. Leave blank for default.',
          ),
        ],
        const SizedBox(height: 12),
        _formCheckboxTile(
          title: 'Set as default target',
          value: _isDefault,
          onChanged: (value) {
            setState(() => _isDefault = value ?? false);
          },
        ),
      ],
    );
  }

  /// True when the SSH user matches the host's service account, which cannot
  /// authenticate. Compared against the service-account field so a nonstandard
  /// contract is still handled, falling back to the default when it is blank.
  bool get _usernameLooksLikeServiceAccount {
    if (widget.targetType != 'akida') return false;
    final username = _usernameController.text.trim().toLowerCase();
    if (username.isEmpty) return false;
    final serviceUser = _serviceUserController.text.trim().toLowerCase();
    return username == (serviceUser.isEmpty ? 'neurochip' : serviceUser);
  }

  /// The password to submit, using `null` for "leave the saved one alone".
  ///
  /// Three distinct intents, which a plain `String` cannot express:
  /// - `null` — the masked placeholder is untouched, so the key is omitted and
  ///   the backend keeps what it has.
  /// - `''` — the user deliberately emptied a previously-saved field, which must
  ///   clear the stored password rather than silently keep it.
  /// - anything else — the password the user typed.
  ///
  /// Deliberately independent of [_authMode]: a typed secret used to be dropped
  /// whenever the auth toggle disagreed with it, which is how passwords went
  /// missing. The backend reconciles the mode against the credentials it
  /// actually receives.
  String? _submittedPassword() {
    final text = _passwordController.text;
    final hasSavedPassword = switch (widget.targetType) {
      'akida' => _akidaHasSavedPassword,
      'pynq' => _pynqHasSavedPassword,
      _ => false,
    };
    if (hasSavedPassword && text == _savedPasswordMask) return null;
    if (text.isEmpty && !hasSavedPassword) return null;
    return text;
  }

  HardwareTargetFormResult _buildFormResult() {
    var password = _submittedPassword();
    final sameHostAsBackend =
        widget.targetType == 'akida' && _sameHostAsBackend;
    var host = _hostController.text.trim();
    var username = _usernameController.text.trim();
    var sshKeyPath = _sshKeyPathController.text.trim();
    var runtimeApiUrl = _runtimeApiUrlController.text.trim();
    var controlApiUrl = _controlApiUrlController.text.trim();

    if (sameHostAsBackend && (widget.initialEntry?.id.isEmpty ?? true)) {
      // "Same machine as your backend server" means the app already holds the
      // connection to that box, so a brand-new target takes the backend's own
      // address and needs no SSH credentials. The runtime/control URLs are
      // cleared so launcher control derives them from the address using its
      // contract ports. An existing record keeps whatever it was created with,
      // which preserves a same-host target that already carries SSH details.
      final backendHost = _backendHostAddress();
      if (backendHost != null && backendHost.isNotEmpty) {
        host = backendHost;
        runtimeApiUrl = '';
        controlApiUrl = '';
      }
      // Drop any SSH details the user typed before ticking the box: a same-host
      // entry is name-only, so stale credentials must not ride along on save.
      username = '';
      sshKeyPath = '';
      password = null;
    }

    return HardwareTargetFormResult(
      editingEntryId: widget.initialEntry?.id,
      displayName: _displayNameController.text.trim().isEmpty
          ? host
          : _displayNameController.text.trim(),
      host: host,
      username: username,
      sshPort: int.tryParse(_sshPortController.text.trim()) ?? 22,
      authMode: _authMode,
      credentialRef: _credentialRefController.text.trim(),
      password: password,
      sshKeyPath: sshKeyPath,
      runtimeApiUrlOverride: _runtimeApiUrlOverrideController.text.trim(),
      overlayVersion: _overlayVersionController.text.trim(),
      runtimeApiUrl: runtimeApiUrl,
      controlApiUrl: controlApiUrl,
      remoteInstallRoot: _remoteInstallRootController.text.trim(),
      serviceUser: _serviceUserController.text.trim(),
      isDefault: _isDefault,
      sameHostAsBackend: sameHostAsBackend,
      // SC-NeuroCore FPGA synthesis fields.
      scFamily: _scFamily,
      scToolchain: _scToolchain,
      scDeviceSpec: _deviceSpecController.text.trim(),
      scDeploymentMode: _scDeploymentMode,
      scHost: _hostController.text.trim(),
      scSshPort: int.tryParse(_sshPortController.text.trim()) ?? 22,
      scUsername: _usernameController.text.trim(),
      scSshKeyPath: _sshKeyPathController.text.trim(),
      scToolchainBinPath: _toolchainBinPathController.text.trim(),
      scOutputDirectory: _outputDirectoryController.text.trim(),
    );
  }

  Future<void> _handleSave() async {
    final form = _buildFormResult();

    if (widget.targetType == 'sc_neurocore_fpga') {
      final checkService = ScNeuroCoreToolchainCheckService(
        ref.read(apiClientProvider),
      );
      final installed = await checkService.looksInstalled(
        _scToolchain,
        binPath: form.scToolchainBinPath,
      );
      if (!installed) {
        final shouldProceed = await _showToolchainWarningDialog();
        if (shouldProceed != true) {
          return;
        }
      }
    }

    await widget.onSave(form);
  }

  Future<bool?> _showToolchainWarningDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: NmtkDesignTokens.dialogShape,
        ),
        backgroundColor: AppTheme.surface,
        title: const Row(
          children: [
            Icon(ZetaIcons.warning_outline, color: AppTheme.warning, size: 24),
            SizedBox(width: 8),
            Text('Toolchain not found'),
          ],
        ),
        content: Text(
          'The selected toolchain could not be found on the server running CNL Studio. '
          'Synthesis will fail unless it is installed before deployment.\\n\\n'
          'Are you sure you want to save this target anyway?',
          style: Zeta.of(
            context,
          ).textStyles.bodyMedium.copyWith(color: AppTheme.textPrimary),
        ),
        actions: [
          ZetaButton.text(
            onPressed: () => Navigator.of(ctx).pop(false),
            label: 'Cancel',
          ),
          ZetaButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            label: 'Save Anyway',
          ),
        ],
      ),
    );
  }
}
