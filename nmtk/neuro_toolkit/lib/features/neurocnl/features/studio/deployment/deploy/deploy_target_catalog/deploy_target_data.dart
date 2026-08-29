import 'package:flutter/material.dart';

class DeployTargetData {
  const DeployTargetData({
    required this.id,
    required this.label,
    required this.icon,
    required this.kind,
    this.trainable = false,
  });

  final String id;
  final String label;
  final IconData icon;

  /// 'simulator' | 'codegen' | 'hardware' — static mirror of
  /// nir_support.SIMULATOR_RUNTIME_BACKENDS, kept client-side/synchronous
  /// (not derived from the live GET /deploy-targets endpoint) so it's
  /// available on the very first frame with no network dependency.
  final String kind;

  /// Whether Play trains this target. Static mirror of the backend's
  /// `_TRAINABLE_NOTEBOOK_TARGETS` (app/routers/notebook.py), same rationale as
  /// [kind]: Setup has to badge a target before any notebook is generated, so
  /// it cannot wait for `GenerateV2Response.trainable`.
  ///
  /// This is a *label*, never a gate — the run/skip decision is always made
  /// from the backend's response, so a drift here mislabels a tile but cannot
  /// cause a notebook to be run or skipped wrongly.
  final bool trainable;
}
