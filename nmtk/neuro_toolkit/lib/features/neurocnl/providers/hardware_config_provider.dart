import 'package:neuro_toolkit/features/neurocnl/models/template.dart';

/// Holds the hardware config selected from a template.
/// Set when a template with a known hardware preset is loaded.
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'hardware_config_provider.g.dart';

@riverpod
class SelectedHardwareConfigController
    extends _$SelectedHardwareConfigController {
  @override
  HardwareConfig? build() => null;

  void setState(HardwareConfig? config) => state = config;
}

final selectedHardwareConfigProvider = selectedHardwareConfigControllerProvider;
