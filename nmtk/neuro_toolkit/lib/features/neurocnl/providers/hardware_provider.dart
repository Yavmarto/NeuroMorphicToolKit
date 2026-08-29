import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:neuro_toolkit/features/neurocnl/models/sensor_frame.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';

part 'hardware_provider.g.dart';

/// State for hardware connection and sensor streaming.
class HardwareState {
  final bool isConnected;
  final String? connectedPort;
  final List<String> availablePorts;
  final List<SensorFrame> sensorData;
  final bool isRefreshing;
  final String? errorMessage;

  const HardwareState({
    this.isConnected = false,
    this.connectedPort,
    this.availablePorts = const [],
    this.sensorData = const [],
    this.isRefreshing = false,
    this.errorMessage,
  });

  HardwareState copyWith({
    bool? isConnected,
    String? connectedPort,
    List<String>? availablePorts,
    List<SensorFrame>? sensorData,
    bool? isRefreshing,
    String? errorMessage,
    bool clearPort = false,
    bool clearError = false,
  }) {
    return HardwareState(
      isConnected: isConnected ?? this.isConnected,
      connectedPort: clearPort ? null : (connectedPort ?? this.connectedPort),
      availablePorts: availablePorts ?? this.availablePorts,
      sensorData: sensorData ?? this.sensorData,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

@riverpod
class HardwareController extends _$HardwareController {
  StreamSubscription<SensorFrame>? _sensorSubscription;

  @override
  HardwareState build() {
    ref.onDispose(() {
      _sensorSubscription?.cancel();
    });
    return const HardwareState();
  }

  /// Refresh the list of available serial ports.
  Future<void> refreshPorts() async {
    final api = ref.read(apiClientProvider);

    state = state.copyWith(isRefreshing: true, clearError: true);
    try {
      final ports = await api.listSerialPorts();
      if (!ref.mounted) return;
      state = state.copyWith(availablePorts: ports, isRefreshing: false);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isRefreshing: false,
        errorMessage: 'Failed to list ports: $e',
      );
    }
  }

  /// Connect to a serial port at the given baud rate.
  Future<void> connect(String port, int baudRate) async {
    final api = ref.read(apiClientProvider);

    state = state.copyWith(clearError: true);
    try {
      await api.connectHardware(port, baudRate);
      if (!ref.mounted) return;
      state = state.copyWith(
        isConnected: true,
        connectedPort: port,
        sensorData: [],
      );
      _startSensorStream(api);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(errorMessage: 'Connection failed: $e');
    }
  }

  /// Disconnect from the current hardware port.
  Future<void> disconnect() async {
    final api = ref.read(apiClientProvider);

    unawaited(_sensorSubscription?.cancel());
    try {
      await api.disconnectHardware();
    } catch (e) {
      // Best-effort disconnect.
      debugPrint('Failed to disconnect hardware port: $e');
    }
    if (!ref.mounted) return;
    state = const HardwareState();
  }

  void _startSensorStream(ApiClient api) {
    _sensorSubscription?.cancel();
    _sensorSubscription = api.streamHardwareSensorData().listen(
      (frame) {
        if (!ref.mounted) return;
        final nextFrames = [...state.sensorData, frame];
        if (nextFrames.length > 256) {
          nextFrames.removeRange(0, nextFrames.length - 256);
        }
        state = state.copyWith(sensorData: nextFrames, clearError: true);
      },
      onError: (Object error) {
        if (!ref.mounted) return;
        state = state.copyWith(errorMessage: 'Sensor stream failed: $error');
      },
    );
  }

  /// Start live sensor streaming from the backend SSE endpoint.
  void startSensorPolling({Duration interval = const Duration(seconds: 1)}) {
    final api = ref.read(apiClientProvider);
    _startSensorStream(api);
  }

  /// Stop sensor polling.
  void stopSensorPolling() {
    _sensorSubscription?.cancel();
  }

  /// Reset to initial state.
  void reset() {
    _sensorSubscription?.cancel();
    state = const HardwareState();
  }
}

/// Backward-compat alias.
final hardwareProvider = hardwareControllerProvider;
