import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/simulator_preflight.dart'; // ignore: unused_import
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';

part 'simulator_preflight_provider.g.dart';

// ── Status enum ──────────────────────────────────────────────────────────────

/// Lifecycle status of a single preflight check.
enum SimulatorPreflightStatus { idle, running, success, error }

// ── Immutable state ──────────────────────────────────────────────────────────

class SimulatorPreflightState {
  const SimulatorPreflightState({
    this.status = SimulatorPreflightStatus.idle,
    this.backendName,
    this.level,
    this.supportedNodes = const [],
    this.approximateNodes = const [],
    this.unsupportedNodes = const [],
    this.diagnostics = const [],
    this.errorMessage,
    this.overrideMode = false,
  });

  final SimulatorPreflightStatus status;
  final String? backendName;
  final String? level;
  final List<String> supportedNodes;
  final List<String> approximateNodes;
  final List<String> unsupportedNodes;
  final List<String> diagnostics;
  final String? errorMessage;
  final bool overrideMode;

  bool get runsBlocked =>
      (status == SimulatorPreflightStatus.running) ||
      (level == 'unsupported' && !overrideMode);

  SimulatorPreflightState copyWith({
    SimulatorPreflightStatus? status,
    String? backendName,
    String? level,
    List<String>? supportedNodes,
    List<String>? approximateNodes,
    List<String>? unsupportedNodes,
    List<String>? diagnostics,
    String? errorMessage,
    bool? overrideMode,
    bool clearLevel = false,
    bool clearError = false,
  }) => SimulatorPreflightState(
    status: status ?? this.status,
    backendName: backendName ?? this.backendName,
    level: clearLevel ? null : (level ?? this.level),
    supportedNodes: supportedNodes ?? this.supportedNodes,
    approximateNodes: approximateNodes ?? this.approximateNodes,
    unsupportedNodes: unsupportedNodes ?? this.unsupportedNodes,
    diagnostics: diagnostics ?? this.diagnostics,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    overrideMode: overrideMode ?? this.overrideMode,
  );
}

// ── Notifier ─────────────────────────────────────────────────────────────────

@riverpod
class SimulatorPreflightController extends _$SimulatorPreflightController {
  String? _currentKey;

  @override
  SimulatorPreflightState build() => const SimulatorPreflightState();

  Future<void> runPreflight(String spec, String backendName) async {
    final key = '$backendName:${spec.hashCode}';
    if (_currentKey == key &&
        state.status == SimulatorPreflightStatus.running) {
      return;
    }
    _currentKey = key;
    state = SimulatorPreflightState(
      status: SimulatorPreflightStatus.running,
      backendName: backendName,
    );

    try {
      final result = await ref
          .read(apiClientProvider)
          .preflight(spec, backendName);
      if (!ref.mounted || _currentKey != key) return;
      state = SimulatorPreflightState(
        status: SimulatorPreflightStatus.success,
        backendName: backendName,
        level: result.level,
        supportedNodes: result.supportedNodes,
        approximateNodes: result.approximateNodes,
        unsupportedNodes: result.unsupportedNodes,
        diagnostics: result.diagnostics,
      );
    } on ApiException catch (e) {
      if (!ref.mounted || _currentKey != key) return;
      state = SimulatorPreflightState(
        status: SimulatorPreflightStatus.error,
        backendName: backendName,
        errorMessage: _extractErrorMessage(e),
      );
    }
  }

  Future<void> runPreflightNir(Uint8List nirBytes, String backendName) async {
    final key = '$backendName:${nirBytes.hashCode}';
    if (_currentKey == key &&
        state.status == SimulatorPreflightStatus.running) {
      return;
    }
    _currentKey = key;
    state = SimulatorPreflightState(
      status: SimulatorPreflightStatus.running,
      backendName: backendName,
    );

    try {
      final result = await ref
          .read(apiClientProvider)
          .preflightNir(nirBytes, backendName);
      if (!ref.mounted || _currentKey != key) return;
      state = SimulatorPreflightState(
        status: SimulatorPreflightStatus.success,
        backendName: backendName,
        level: result.level,
        supportedNodes: result.supportedNodes,
        approximateNodes: result.approximateNodes,
        unsupportedNodes: result.unsupportedNodes,
        diagnostics: result.diagnostics,
      );
    } on ApiException catch (e) {
      if (!ref.mounted || _currentKey != key) return;
      state = SimulatorPreflightState(
        status: SimulatorPreflightStatus.error,
        backendName: backendName,
        errorMessage: _extractErrorMessage(e),
      );
    }
  }

  void setOverrideMode(bool value) {
    state = state.copyWith(overrideMode: value);
  }

  void invalidate() {
    _currentKey = null;
    state = const SimulatorPreflightState();
  }

  String _extractErrorMessage(ApiException e) {
    try {
      final decoded = jsonDecode(e.body) as Map<String, dynamic>;
      final detail = decoded['detail'];
      if (detail is String) return detail;
      if (detail is Map && detail['message'] is String) {
        return detail['message'] as String;
      }
    } catch (parseError) {
      debugPrint('Failed to decode preflight error detail: $parseError');
    }
    return 'Preflight failed (HTTP ${e.statusCode})';
  }
}

/// Backward-compat alias.
final simulatorPreflightProvider = simulatorPreflightControllerProvider;
