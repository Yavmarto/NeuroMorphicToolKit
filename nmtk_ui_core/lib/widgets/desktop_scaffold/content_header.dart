part of '../desktop_scaffold.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONTENT HEADER (back button + file actions)
// ─────────────────────────────────────────────────────────────────────────────

/// Optional header bar rendered above the content area when [showBackButton]
/// is true or any file action callback is provided.
class _NmtkContentHeader extends StatelessWidget {
  const _NmtkContentHeader({
    required this.showBackButton,
    this.onBack,
    this.onNewFile,
    this.onOpenFile,
    this.onSaveFile,
    this.onSaveFileAs,
  });

  final bool showBackButton;
  final VoidCallback? onBack;
  final OnNewFile? onNewFile;
  final OnOpenFile? onOpenFile;
  final OnSaveFile? onSaveFile;
  final OnSaveFileAs? onSaveFileAs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SizedBox(
        height: _kContentHeaderHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              // ── Back button (animated) ──────────────────────────────
              AnimatedOpacity(
                opacity: showBackButton ? 1.0 : 0.0,
                duration: _kBackButtonAnimDuration,
                curve: _kBackButtonAnimCurve,
                child: AnimatedSlide(
                  offset: showBackButton ? Offset.zero : const Offset(-0.5, 0),
                  duration: _kBackButtonAnimDuration,
                  curve: _kBackButtonAnimCurve,
                  child: Tooltip(
                    message: 'Back',
                    child: ZetaIconButton(
                      icon: ZetaIcons.arrow_back,
                      type: ZetaButtonType.text,
                      size: ZetaWidgetSize.small,
                      semanticLabel: 'Back',
                      onPressed: showBackButton ? onBack : null,
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // ── File action icon strip ──────────────────────────────
              if (onNewFile != null)
                _FileActionIconButton(
                  icon: ZetaIcons.add,
                  tooltip: 'New File\n⌘N / Ctrl+N',
                  onPressed: onNewFile!,
                ),
              if (onOpenFile != null)
                _FileActionIconButton(
                  icon: ZetaIcons.folder_outline,
                  tooltip: 'Open File\n⌘O / Ctrl+O',
                  onPressed: onOpenFile!,
                ),
              if (onSaveFile != null)
                _FileActionIconButton(
                  icon: ZetaIcons.save,
                  tooltip: 'Save\n⌘S / Ctrl+S',
                  onPressed: onSaveFile!,
                ),
              if (onSaveFileAs != null)
                _FileActionIconButton(
                  icon: ZetaIcons.save_alt,
                  tooltip: 'Save As\n⌘⇧S / Ctrl+Shift+S',
                  onPressed: onSaveFileAs!,
                ),
              if (onNewFile != null ||
                  onOpenFile != null ||
                  onSaveFile != null ||
                  onSaveFileAs != null)
                const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Individual file-action icon button ─────────────────────────────────────────

class _FileActionIconButton extends StatelessWidget {
  const _FileActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: ZetaIconButton(
        icon: icon,
        type: ZetaButtonType.text,
        size: ZetaWidgetSize.small,
        semanticLabel: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FILE ACTION KEYBOARD SHORTCUTS
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps [child] with [CallbackShortcuts] that fire file action callbacks
/// on Cmd/Ctrl+N, +O, +S and Cmd/Ctrl+Shift+S.
class _FileActionShortcuts extends StatelessWidget {
  const _FileActionShortcuts({
    required this.child,
    this.onNewFile,
    this.onOpenFile,
    this.onSaveFile,
    this.onSaveFileAs,
  });

  final OnNewFile? onNewFile;
  final OnOpenFile? onOpenFile;
  final OnSaveFile? onSaveFile;
  final OnSaveFileAs? onSaveFileAs;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bindings = <ShortcutActivator, VoidCallback>{};

    if (onNewFile != null) {
      bindings[const SingleActivator(LogicalKeyboardKey.keyN, meta: true)] =
          onNewFile!;
      bindings[const SingleActivator(LogicalKeyboardKey.keyN, control: true)] =
          onNewFile!;
    }

    if (onOpenFile != null) {
      bindings[const SingleActivator(LogicalKeyboardKey.keyO, meta: true)] =
          onOpenFile!;
      bindings[const SingleActivator(LogicalKeyboardKey.keyO, control: true)] =
          onOpenFile!;
    }

    if (onSaveFile != null) {
      bindings[const SingleActivator(LogicalKeyboardKey.keyS, meta: true)] =
          onSaveFile!;
      bindings[const SingleActivator(LogicalKeyboardKey.keyS, control: true)] =
          onSaveFile!;
    }

    if (onSaveFileAs != null) {
      bindings[const SingleActivator(
            LogicalKeyboardKey.keyS,
            meta: true,
            shift: true,
          )] =
          onSaveFileAs!;
      bindings[const SingleActivator(
            LogicalKeyboardKey.keyS,
            control: true,
            shift: true,
          )] =
          onSaveFileAs!;
    }

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(autofocus: true, child: child),
    );
  }
}
