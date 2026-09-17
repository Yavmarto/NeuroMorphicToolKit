library;

import 'package:flutter/material.dart';

class MobileDeployAction {
  const MobileDeployAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String id;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  bool matchesPresentation(MobileDeployAction other) =>
      id == other.id &&
      label == other.label &&
      icon == other.icon &&
      (onPressed == null) == (other.onPressed == null);
}
