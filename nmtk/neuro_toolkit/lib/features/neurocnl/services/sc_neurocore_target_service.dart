// Local CRUD service for SC-NeuroCore synthesis targets.
//
// SC-NeuroCore FPGA targets are stored locally in SharedPreferences as a JSON
// list under [_prefsKey].  No network calls are made — unlike Akida/PYNQ, this
// target's configuration is entirely client-side (it describes local toolchain
// arguments, not a remote SSH host).

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/sc_neurocore_synthesis_target.dart';

/// Riverpod provider for [ScNeuroCoreTargetService].
final scNeuroCoreTargetServiceProvider = Provider<ScNeuroCoreTargetService>((
  ref,
) {
  return ScNeuroCoreTargetService();
});

class ScNeuroCoreTargetService {
  static const String _prefsKey = 'sc_neurocore_targets';

  /// Returns all stored synthesis targets.
  Future<List<ScNeuroCoreTarget>> fetchTargets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return const <ScNeuroCoreTarget>[];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <ScNeuroCoreTarget>[];
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(ScNeuroCoreTarget.fromJson)
        .toList(growable: false);
  }

  /// Saves (create or update) a synthesis target.
  ///
  /// When [target.id] is empty a new UUID-style ID is generated from the
  /// current timestamp.  If [target.isDefault] is true every other target is
  /// demoted.  Returns the saved target.
  Future<ScNeuroCoreTarget> saveTarget(ScNeuroCoreTarget target) async {
    final prefs = await SharedPreferences.getInstance();
    var targets = await fetchTargets();

    final id = target.id.isEmpty
        ? 'sc_nc_${DateTime.now().millisecondsSinceEpoch}'
        : target.id;
    final saved = target.copyWith(id: id);

    // Demote other defaults when this one is set as default.
    if (saved.isDefault) {
      targets = targets
          .map((t) => t.id == id ? t : t.copyWith(isDefault: false))
          .toList();
    }

    final idx = targets.indexWhere((t) => t.id == id);
    if (idx >= 0) {
      targets[idx] = saved;
    } else {
      targets = [...targets, saved];
    }

    await prefs.setString(
      _prefsKey,
      jsonEncode(targets.map((t) => t.toJson()).toList()),
    );
    return saved;
  }

  /// Deletes the target with [id].  No-op if [id] is not found.
  Future<void> deleteTarget(String id) async {
    final prefs = await SharedPreferences.getInstance();
    var targets = await fetchTargets();
    targets = targets.where((t) => t.id != id).toList();
    await prefs.setString(
      _prefsKey,
      jsonEncode(targets.map((t) => t.toJson()).toList()),
    );
  }
}
