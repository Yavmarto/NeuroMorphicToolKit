import 'package:flutter/material.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_assistant_panel.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

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
    return widget.isMobile ?? MediaQuery.sizeOf(context).width < 900;
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
          widget.child,
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'studio-assistant-fab',
              onPressed: () => _openAssistant(context),
              icon: Icon(
                ZetaIcons.chat,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              label: const Text('Assistant'),
            ),
          ),
        ],
      ),
    );
  }
}
