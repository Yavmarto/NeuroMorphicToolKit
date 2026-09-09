import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/screens/server_access_popup.dart';

/// Decides whether to show the workspace or a sign-in/setup flow at app start.
///
/// The workspace ([child]) is always mounted as the backdrop. When there is no
/// live session — cold start with no saved server, a failed reconnect, or a
/// sign-out — an adaptive popup (dialog on desktop, bottom sheet on phones)
/// with the sign-in / set-up-a-new-server flow is overlaid on top of it.
///
/// On mount it tries [ConnectNotifier.reconnectOnOpen]: when the saved
/// credential still works it resolves to `connected` fast and the popup is
/// closed / never shown — the user sees the workspace immediately. When there
/// is no saved server, or reconnect fails, the popup is shown instead; from
/// there the user can sign in or set up a brand-new server.
class ServerAccessGate extends ConsumerStatefulWidget {
  const ServerAccessGate({super.key, required this.child});

  /// The workspace surface shown once a session is connected.
  final Widget child;

  @override
  ConsumerState<ServerAccessGate> createState() => _ServerAccessGateState();
}

class _ServerAccessGateState extends ConsumerState<ServerAccessGate> {
  bool _reconnectTriggered = false;
  bool _reconnectPending = false;
  bool _popupOpen = false;
  bool _popupDismissed = false;

  @override
  void initState() {
    super.initState();
    _reconnectTriggered = true;
    _reconnectPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final phase = ref.read(connectNotifierProvider).phase;
      if (!_isConnectedPhase(phase)) {
        // Fire-and-forget; the notifier updates [connectNotifierProvider],
        // which this widget watches to decide what to render.
        ref.read(connectNotifierProvider.notifier).reconnectOnOpen().whenComplete(
          () {
            _reconnectPending = false;
            if (!mounted) return;
            _syncPopup(ref.read(connectNotifierProvider).phase);
          },
        );
      } else {
        _reconnectPending = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(connectNotifierProvider);
    ref.listen<ConnectState>(connectNotifierProvider, (previous, next) {
      _handleConnectionStateChange(previous, next);
    });
    ref.listen<int>(serverAccessPopupRequestProvider, (previous, next) {
      if (next > (previous ?? 0) &&
          !_isConnectedPhase(ref.read(connectNotifierProvider).phase)) {
        _popupDismissed = false;
        _syncPopup(ref.read(connectNotifierProvider).phase);
      }
    });

    final showReconnectingOverlay =
        _reconnectTriggered &&
        state.phase == ConnectPhase.reconnecting &&
        !_popupOpen;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (showReconnectingOverlay)
          const Positioned.fill(
            child: ModalBarrier(
              dismissible: false,
              color: Colors.black26,
            ),
          ),
        if (showReconnectingOverlay)
          const Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ZetaProgressCircle(size: ZetaCircleSizes.s),
                SizedBox(width: 12),
                Flexible(
                  child: Text(
                    'Reconnecting to your server…',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _handleConnectionStateChange(ConnectState? previous, ConnectState next) {
    final prevPhase = previous?.phase;
    final nowConnected = _isConnectedPhase(next.phase);

    if (nowConnected) {
      if (_popupOpen) {
        _closePopup();
      }
      return;
    }

    // Logged out from a connected workspace (or the workspace's connect dot /
    // change-server actions): bring the popup back, even if it was dismissed.
    if (_isConnectedPhase(prevPhase)) {
      _popupDismissed = false;
      _syncPopup(next.phase);
      return;
    }

    _syncPopup(next.phase);
  }

  /// Opens or closes the popup to match the current phase. The popup shows
  /// for `idle` and `failed` (cold start with nothing to reconnect, or a
  /// failed reconnect); it stays hidden while a reconnect is still in flight
  /// and when the user has explicitly dismissed it.
  void _syncPopup(ConnectPhase phase) {
    if (!_reconnectTriggered || _isConnectedPhase(phase)) {
      return;
    }
    final wantsPopup =
        (phase == ConnectPhase.idle || phase == ConnectPhase.failed) &&
        !_popupDismissed &&
        !_reconnectPending;
    if (wantsPopup && !_popupOpen) {
      _openPopup();
    } else if (!wantsPopup && _popupOpen) {
      _closePopup();
    }
  }

  void _openPopup() {
    if (_popupOpen || !mounted) return;
    _popupOpen = true;
    showServerAccessPopup(context).whenComplete(() {
      _popupOpen = false;
      final phase = ref.read(connectNotifierProvider).phase;
      if (!_isConnectedPhase(phase)) {
        _popupDismissed = true;
      }
      if (mounted) setState(() {});
    });
  }

  void _closePopup() {
    if (!_popupOpen || !mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
    _popupOpen = false;
  }

  static bool _isConnectedPhase(ConnectPhase? phase) =>
      phase == ConnectPhase.connected || phase == ConnectPhase.devOffline;
}
