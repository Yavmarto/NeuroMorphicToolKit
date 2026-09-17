import 'package:flutter/material.dart';

class DeployTargetData {
  const DeployTargetData({
    required this.id,
    required this.label,
    required this.icon,
    this.trainable = false,
    this.runtimeCapable = false,
    this.deployCapable = false,
  });

  final String id;
  final String label;
  final IconData icon;

  /// Whether Play trains this target. Static mirror of the backend's
  /// `_TRAINABLE_NOTEBOOK_TARGETS` (app/routers/notebook.py), same rationale as
  /// the capability flags below: Setup has to badge a target before any notebook
  /// is generated, so it cannot wait for `GenerateV2Response.trainable`.
  ///
  /// This is a *label*, never a gate — the run/skip decision is always made
  /// from the backend's response, so a drift here mislabels a tile but cannot
  /// cause a notebook to be run or skipped wrongly.
  final bool trainable;

  /// Whether Deploy shows a Run row for this target (in-app simulators and
  /// notebook-backed framework runtimes). Static mirror of
  /// `SIMULATOR_RUNTIME_BACKENDS` plus framework backends that have a
  /// notebook runtime path — kept client-side so the Deploy step can lay out
  /// rows on the first frame without waiting on GET /deploy-targets.
  final bool runtimeCapable;

  /// Whether this target deploys to paired hardware (Akida, PYNQ, FPGA, etc.).
  /// `lava` is both runtime- and deploy-capable; it defaults to simulator mode
  /// and only becomes real Loihi2 hardware when toggled inside Configure.
  final bool deployCapable;
}
