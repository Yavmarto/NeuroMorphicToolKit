import 'package:flutter/widgets.dart';

/// ----------------------------------------------------------------------------
/// NMTK KEYBOARD INTENTS
/// ----------------------------------------------------------------------------

class ToggleCommandPaletteIntent extends Intent {
  const ToggleCommandPaletteIntent();
}

class ToggleSidebarIntent extends Intent {
  const ToggleSidebarIntent();
}

class SaveIntent extends Intent {
  const SaveIntent();
}

class SearchIntent extends Intent {
  const SearchIntent();
}

/// ----------------------------------------------------------------------------
/// NMTK COMMAND MODEL
/// ----------------------------------------------------------------------------

class NmtkCommand {
  final String id;
  final String label;
  final String? description;
  final IconData? icon;
  final VoidCallback onExecute;
  final List<String>? aliases;
  final bool global;
  final String? category;

  const NmtkCommand({
    required this.id,
    required this.label,
    this.description,
    this.icon,
    required this.onExecute,
    this.aliases,
    this.global = true,
    this.category,
  });
}
