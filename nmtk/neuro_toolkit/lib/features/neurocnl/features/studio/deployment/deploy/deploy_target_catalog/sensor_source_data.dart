import 'package:flutter/material.dart';

/// A live data-acquisition source available to Studio's setup stage.
///
/// Deliberately separate from [DeployTargetData]: a sensor source doesn't
/// train a model, doesn't run inference, and isn't deployed to — it emits
/// samples. Forcing it into `trainable`/`runtimeCapable`/`deployCapable`
/// would misrepresent what it does, so this type carries none of those
/// flags.
class SensorSourceData {
  const SensorSourceData({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}
