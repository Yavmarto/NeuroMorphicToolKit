import 'package:flutter/material.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_assistant_panel.dart';
import 'package:neuro_toolkit/ui_core/contrast_utils.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Exposes [StudioAssistantHost]'s open-assistant action to descendants so a
/// mobile shell's app bar can trigger the same bottom sheet the (now
/// removed) mobile FAB used to open.
class StudioAssistantScope extends InheritedWidget {
  const StudioAssistantScope({
    super.key,
    required this.openAssistant,
    required super.child,
  });

  final VoidCallback openAssistant;

  static VoidCallback? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<StudioAssistantScope>()
        ?.openAssistant;
  }

  @override
  bool updateShouldNotify(StudioAssistantScope oldWidget) =>
      openAssistant != oldWidget.openAssistant;
}

/// Wraps Studio content with an assistant drawer (desktop) or bottom sheet (mobile).
class StudioAssistantHost extends StatefulWidget {
  const StudioAssistantHost({super.key, required this.child, this.isMobile});

  final Widget child;
  final bool? isMobile;

  @override
  State<StudioAssistantHost> createState() => _StudioAssistantHostState();
}

class _StudioAssistantHostState extends State<StudioAssistantHost> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _isMobile(BuildContext context) {
    return widget.isMobile ??
        MediaQuery.sizeOf(context).width < NmtkShellTokens.compactBreakpoint;
  }

  void _openAssistant(BuildContext context) {
    if (_isMobile(context)) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(NmtkShellTokens.of(context).radiusLg),
          ),
        ),
        builder: (sheetContext) {
          final keyboardInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
          return Padding(
            padding: EdgeInsets.only(bottom: keyboardInset),
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.82,
              child: StudioAssistantPanel(
                onClose: () => Navigator.of(sheetContext).pop(),
              ),
            ),
          );
        },
      );
      return;
    }
    _scaffoldKey.currentState?.openEndDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    final scheme = Theme.of(context).colorScheme;
    final fabInk = nmtkReadableForeground(
      scheme.onPrimary,
      scheme.primary,
      floor: 3.0,
    );
    // Mobile no longer gets a floating launcher — the assistant is opened
    // from an action in the mobile shell's app bar via StudioAssistantScope
    // instead, so it can't cover step content or be mistaken for a
    // draggable canvas element.
    final launcher = FloatingActionButton.extended(
      heroTag: 'studio-assistant-fab',
      onPressed: () => _openAssistant(context),
      icon: Icon(ZetaIcons.chat, color: fabInk),
      label: const Text('Assistant'),
    );
    return Scaffold(
      key: _scaffoldKey,
      endDrawer: mobile
          ? null
          : Drawer(
              width: 380,
              child: StudioAssistantPanel(
                onClose: () => _scaffoldKey.currentState?.closeEndDrawer(),
              ),
            ),
      body: Stack(
        children: [
          StudioAssistantScope(
            openAssistant: () => _openAssistant(context),
            child: widget.child,
          ),
          if (!mobile) Positioned(right: 16, bottom: 16, child: launcher),
        ],
      ),
    );
  }
}
