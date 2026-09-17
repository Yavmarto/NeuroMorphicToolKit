import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keyboard shortcut sink for Studio — Cmd/Ctrl+Enter run, save/open/new file.
class StudioKeyboardShortcutScope extends StatelessWidget {
  const StudioKeyboardShortcutScope({
    super.key,
    required this.onTriggerRun,
    required this.onSaveWorkspace,
    required this.onSaveWorkspaceAs,
    required this.onOpenWorkspace,
    required this.onNewFile,
    required this.child,
  });

  final VoidCallback onTriggerRun;
  final VoidCallback onSaveWorkspace;
  final VoidCallback onSaveWorkspaceAs;
  final VoidCallback onOpenWorkspace;
  final VoidCallback onNewFile;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
            onTriggerRun,
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            onTriggerRun,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            onSaveWorkspace,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            onSaveWorkspace,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true):
            onSaveWorkspaceAs,
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          control: true,
          shift: true,
        ): onSaveWorkspaceAs,
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true):
            onOpenWorkspace,
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            onOpenWorkspace,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): onNewFile,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            onNewFile,
      },
      child: Focus(skipTraversal: true, autofocus: true, child: child),
    );
  }
}
