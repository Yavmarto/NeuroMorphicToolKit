import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nmtk_ui_core/models/commands.dart';
import 'package:nmtk_ui_core/widgets/command_palette.dart';

/// ----------------------------------------------------------------------------
/// NMTK SHORTCUT SCOPE
/// ----------------------------------------------------------------------------

class NmtkShortcutScope extends StatelessWidget {
  final Widget child;
  final List<NmtkCommand> globalCommands;

  const NmtkShortcutScope({
    super.key,
    required this.child,
    required this.globalCommands,
  });

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(
          defaultTargetPlatform == TargetPlatform.macOS
              ? LogicalKeyboardKey.meta
              : LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyK,
        ): const ToggleCommandPaletteIntent(),
        LogicalKeySet(
          defaultTargetPlatform == TargetPlatform.macOS
              ? LogicalKeyboardKey.meta
              : LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyS,
        ): const SaveIntent(),
        LogicalKeySet(
          defaultTargetPlatform == TargetPlatform.macOS
              ? LogicalKeyboardKey.meta
              : LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyB,
        ): const ToggleSidebarIntent(),
        LogicalKeySet(
          defaultTargetPlatform == TargetPlatform.macOS
              ? LogicalKeyboardKey.meta
              : LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyF,
        ): const SearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ToggleCommandPaletteIntent:
              CallbackAction<ToggleCommandPaletteIntent>(
                onInvoke: (_) =>
                    NmtkCommandPalette.show(context, commands: globalCommands),
              ),
          // Other intents can be handled here or further down the tree
          ToggleSidebarIntent: CallbackAction<ToggleSidebarIntent>(
            onInvoke: (_) {
              // This will be caught by the DesktopScaffold if it handles this intent
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}
