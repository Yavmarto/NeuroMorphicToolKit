import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/neurosense_workspace/neurosense_setup_pane.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/neurosense_workspace/neurosense_source_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/studio_shared.dart';
import 'package:neuro_toolkit/features/neurocnl/models/neurosense_sensor_target.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/neurosense_popup_header.dart';
import 'package:neuro_toolkit/features/neurocnl/services/file_picker_native_file_backend.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurosense_api_service.dart';

enum NeurosensePopupTab { devices, presets, quality, nir }

Future<void> showNeurosensePopup(
  BuildContext context, {
  NeurosensePopupTab initialTab = NeurosensePopupTab.devices,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => NeurosensePopup(initialTab: initialTab),
  );
}

class NeurosensePopup extends ConsumerStatefulWidget {
  const NeurosensePopup({
    super.key,
    this.initialTab = NeurosensePopupTab.devices,
  });

  final NeurosensePopupTab initialTab;

  @override
  ConsumerState<NeurosensePopup> createState() => _NeurosensePopupState();
}

class _NeurosensePopupState extends ConsumerState<NeurosensePopup> {
  late NeurosensePopupTab _tab;
  List<NeurosenseDeviceInfo> _devices = const [];
  List<NeurosenseAcquisitionPreset> _presets = const [];
  NeurosenseSignalQuality? _quality;
  NeurosenseEncodingConfig? _nirConfig;
  String? _status;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    Future.microtask(_refreshActiveTab);
  }

  NeurosenseApiService get _api => ref.read(neurosenseApiServiceProvider);

  Future<void> _refreshActiveTab() async {
    switch (_tab) {
      case NeurosensePopupTab.devices:
        await _scanDevices();
      case NeurosensePopupTab.presets:
        await _loadPresets();
      case NeurosensePopupTab.quality:
        await _loadQuality();
      case NeurosensePopupTab.nir:
        break;
    }
  }

  Future<void> _scanDevices() async {
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final devices = await _api.listDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _status = devices.isEmpty
            ? 'No devices found. Start the NeuroSense worker or use synthetic mode.'
            : '${devices.length} device(s) available.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Scan failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPresets() async {
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final presets = await _api.listPresets();
      if (!mounted) return;
      setState(() {
        _presets = presets;
        _status = presets.isEmpty
            ? 'No encoding presets reported by the backend.'
            : '${presets.length} preset(s) available.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Could not load presets: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadQuality() async {
    setState(() {
      _loading = true;
      _status = null;
      _quality = null;
    });
    try {
      final quality = await _api.getQuality();
      if (!mounted) return;
      setState(() {
        _quality = quality;
        _status = quality.channels.isEmpty
            ? 'No quality metrics yet. Connect a device first.'
            : 'Quality check for ${quality.channels.length} channel(s).';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Quality check failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect(NeurosenseDeviceInfo device) async {
    setState(() => _status = 'Connecting to ${device.name}…');
    try {
      await _api.connectDevice(
        device.id,
        serialPort: device.serialPort,
        allowExperimental: true,
      );
      if (!mounted) return;
      setState(() => _status = 'Connected to ${device.name}.');
      await _scanDevices();
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Connect failed: $error');
    }
  }

  Future<void> _importNir() async {
    final files = await const FilePickerDialogGateway().pickFiles(
      allowMultiple: false,
      allowedExtensions: const ['nir'],
    );
    if (files == null || files.isEmpty || !mounted) return;

    final file = files.first;
    setState(() {
      _loading = true;
      _status = 'Importing ${file.name}…';
      _nirConfig = null;
    });
    try {
      final config = await _api.importNir(
        filename: file.name,
        bytes: file.bytes,
      );
      if (!mounted) return;
      setState(() {
        _nirConfig = config;
        _status = 'Imported encoding config from ${file.name}.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'NIR import failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectTab(NeurosensePopupTab tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
    unawaited(_refreshActiveTab());
  }

  @override
  Widget build(BuildContext context) {
    final compact = NmtkDialogSurface.isCompact(context);
    final tokens = NmtkShellTokens.of(context);
    final textStyles = Zeta.of(context).textStyles;
    final config = ref.watch(neuroSenseSourceProvider);

    final content = Material(
      color: tokens.shellBackground,
      child: SafeArea(
        child: Column(
          children: <Widget>[
            NeurosensePopupHeader(
              onClose: () => Navigator.of(context).pop(),
              navigation: SizedBox(
                width: compact ? double.infinity : 520,
                child: ZetaSegmentedControl<NeurosensePopupTab>(
                  segments: const <ZetaButtonSegment<NeurosensePopupTab>>[
                    ZetaButtonSegment(
                      value: NeurosensePopupTab.devices,
                      child: Text('Devices'),
                    ),
                    ZetaButtonSegment(
                      value: NeurosensePopupTab.presets,
                      child: Text('Presets'),
                    ),
                    ZetaButtonSegment(
                      value: NeurosensePopupTab.quality,
                      child: Text('Quality'),
                    ),
                    ZetaButtonSegment(
                      value: NeurosensePopupTab.nir,
                      child: Text('NIR'),
                    ),
                  ],
                  selected: _tab,
                  onChanged: _selectTab,
                ),
              ),
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _status!,
                    style: textStyles.bodySmall.copyWith(
                      color: Zeta.of(context).colors.mainSubtle,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _loading && _tab != NeurosensePopupTab.nir
                    ? const Center(child: CircularProgressIndicator())
                    : _tabContent(config),
              ),
            ),
          ],
        ),
      ),
    );

    if (compact) return Dialog.fullscreen(child: content);
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: SizedBox(width: 960, height: 680, child: content),
    );
  }

  Widget _tabContent(NeuroSenseSensorConfig? config) {
    return switch (_tab) {
      NeurosensePopupTab.devices => _devicesTab(config),
      NeurosensePopupTab.presets => _presetsTab(),
      NeurosensePopupTab.quality => _qualityTab(),
      NeurosensePopupTab.nir => _nirTab(),
    };
  }

  Widget _devicesTab(NeuroSenseSensorConfig? config) {
    final scheme = Theme.of(context).colorScheme;
    final healthyColor = NmtkShellTokens.of(context).healthyColor;

    return ListView(
      children: [
        NeurosenseSetupPane(
          config: config,
          onConfigureSource: () => showNeurosenseConfigDialog(context, ref),
          statusMessage: _status,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.icon(
              key: const Key('neurosense-popup-scan'),
              onPressed: _loading ? null : _scanDevices,
              icon: Icon(Icons.refresh, size: 18, color: scheme.onPrimary),
              label: Text(_loading ? 'Scanning…' : 'Scan devices'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final device in _devices)
          Card(
            child: ListTile(
              leading: Icon(
                device.connected ? Icons.sensors : Icons.sensors_off,
                color: device.connected
                    ? healthyColor
                    : scheme.onSurfaceVariant,
              ),
              title: Text(device.name),
              subtitle: Text(
                '${device.type} • ${device.channels} ch @ ${device.samplingRateHz} Hz',
              ),
              trailing: device.connected
                  ? Icon(Icons.check_circle_outline, color: healthyColor)
                  : TextButton(
                      onPressed: () => _connect(device),
                      child: const Text('Connect'),
                    ),
            ),
          ),
      ],
    );
  }

  Widget _presetsTab() {
    if (_presets.isEmpty) {
      return Center(
        child: Text(
          'No presets loaded.',
          style: Zeta.of(context).textStyles.bodyMedium,
        ),
      );
    }
    return ListView.separated(
      itemCount: _presets.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final preset = _presets[index];
        return Card(
          child: ListTile(
            title: Text(preset.name),
            subtitle: Text('${preset.signalType}\n${preset.description}'),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  Widget _qualityTab() {
    final quality = _quality;
    if (quality == null || quality.channels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Connect a device, then run a quality check.',
              style: Zeta.of(context).textStyles.bodyMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('neurosense-popup-quality-refresh'),
              onPressed: _loading ? null : _loadQuality,
              icon: const Icon(Icons.monitor_heart_outlined, size: 18),
              label: const Text('Run quality check'),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        FilledButton.icon(
          key: const Key('neurosense-popup-quality-refresh'),
          onPressed: _loading ? null : _loadQuality,
          icon: const Icon(Icons.monitor_heart_outlined, size: 18),
          label: const Text('Refresh quality check'),
        ),
        const SizedBox(height: 12),
        for (final channel in quality.channels)
          Card(
            child: ListTile(
              title: Text('${channel.label} (ch ${channel.channel})'),
              subtitle: Text(
                '${channel.status.toUpperCase()} • '
                'SNR ${channel.snrDb.toStringAsFixed(1)} dB'
                '${channel.suggestion == null ? '' : '\n${channel.suggestion}'}',
              ),
              isThreeLine: channel.suggestion != null,
            ),
          ),
      ],
    );
  }

  Widget _nirTab() {
    final config = _nirConfig;
    return ListView(
      children: [
        Text(
          'Import a .nir graph and map it to a spike encoding preset.',
          style: Zeta.of(context).textStyles.bodyMedium,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('neurosense-popup-nir-import'),
          onPressed: _loading ? null : _importNir,
          icon: const Icon(Icons.upload_file, size: 18),
          label: Text(_loading ? 'Importing…' : 'Import .nir file'),
        ),
        if (config != null) ...[
          const SizedBox(height: 16),
          const StudioPhaseBanner(
            label: 'Encoding config ready',
            tone: NmtkTone.success,
          ),
          const SizedBox(height: 8),
          NmtkKeyValueRow(label: 'Method', value: config.method),
          NmtkKeyValueRow(label: 'Summary', value: config.summary),
        ],
      ],
    );
  }
}
