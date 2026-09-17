import 'package:flutter/foundation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/sc_neurocore_synthesis_target.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';

/// Checks whether an SC-NeuroCore FPGA toolchain is installed at the
/// configured path before a synthesis target is saved.
///
/// Fails open: a broken or unreachable health check must not block saving
/// the target, so any error is treated as "installed".
class ScNeuroCoreToolchainCheckService {
  const ScNeuroCoreToolchainCheckService(this._client);

  final ApiClient _client;

  Future<bool> looksInstalled(
    ScNeuroCoreToolchain toolchain, {
    required String binPath,
  }) async {
    try {
      final response = await _client.checkScNeuroCoreToolchain(
        toolchain.apiValue,
        binPath: binPath,
      );
      return response['installed'] == true;
    } catch (e) {
      debugPrint('Toolchain health check failed: $e');
      return true;
    }
  }
}
