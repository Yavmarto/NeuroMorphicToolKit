import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/ui_core/shell_tokens.dart';
import 'package:neuro_toolkit/ui_core/widgets/tone.dart';

/// An optional action rendered at the bottom of a [NmtkNotification] card.
class NmtkNotificationAction {
  const NmtkNotificationAction({required this.label, required this.onPressed});

  /// Button label shown on the card, e.g. `Backend Setup`.
  final String label;

  /// Invoked after the card has been dismissed (a macOS-style notification
  /// action clears the banner it belongs to).
  final VoidCallback onPressed;
}

/// Immutable content for one top-right notification banner.
///
/// Mirrors the shape of a macOS Notification Center banner: a rounded card
/// with a leading icon, a title line, a message, an optional action and an
/// optional auto-dismiss timer.
class NmtkNotification {
  const NmtkNotification({
    required this.title,
    required this.message,
    this.key,
    this.tone = NmtkTone.neutral,
    this.icon,
    this.action,
    this.duration,
    this.showCloseButton = true,
    this.onDismissed,
  });

  /// Coalescing key. Pushing another notification with the same [key] while
  /// one is already visible refreshes the existing card in place instead of
  /// stacking a duplicate (used by high-frequency backend error reports).
  final Object? key;

  /// Headline of the banner.
  final String title;

  /// Detail body of the banner.
  final String message;

  /// Tone of the banner; drives the icon, surface and border colours.
  final NmtkTone tone;

  /// Optional leading icon. Defaults to a tone-appropriate [ZetaIcons] glyph.
  final IconData? icon;

  /// Optional action shown on the card. Selecting it dismisses the card and
  /// runs [NmtkNotificationAction.onPressed].
  final NmtkNotificationAction? action;

  /// How long the banner stays up before auto-dismissing. `null` (the default)
  /// keeps the banner until the user closes it or triggers [action] — the
  /// right choice for actionable errors such as backend connection failures.
  final Duration? duration;

  /// Whether the card exposes a close button.
  final bool showCloseButton;

  /// Called when the banner is removed without its [action] being taken
  /// (close button, auto-dismiss, or replacement by a keyed push).
  final VoidCallback? onDismissed;
}

/// Backing store for the banners shown by [NmtkNotificationCenter].
///
/// Plain Flutter [ChangeNotifier] — no app state-management dependency. The
/// owning [NmtkNotificationCenter] listens to this and renders the banners
/// top-right. Public because tests and callers occasionally need to keep their
/// own controller; most callers only use
/// [NmtkNotificationCenter.maybeControllerOf].
class NmtkNotificationCenterController extends ChangeNotifier {
  NmtkNotificationCenterController({
    this.maxVisible = 5,
    this.exitDuration = const Duration(milliseconds: 180),
  });

  /// Maximum number of banners shown at once; the oldest is dropped first.
  final int maxVisible;

  /// Duration of the fade-out applied when a banner is dismissed. Kept in sync
  /// with the design tokens by the owning widget.
  Duration exitDuration;

  final List<_NmtkNotificationEntry> _entries = <_NmtkNotificationEntry>[];
  int _nextId = 0;
  bool _disposed = false;

  /// Visible banners, newest first.
  List<NmtkNotification> get notifications =>
      List<NmtkNotification>.unmodifiable(
        _entries.map((_NmtkNotificationEntry entry) => entry.notification),
      );

  /// Shows [notification], coalescing on [NmtkNotification.key]: a keyed push
  /// that matches a live banner replaces that banner and restarts its timer.
  void push(NmtkNotification notification) {
    if (_disposed) return;
    final replacementIndex = notification.key == null
        ? -1
        : _entries.indexWhere(
            (_NmtkNotificationEntry entry) =>
                entry.notification.key == notification.key,
          );
    if (replacementIndex != -1) {
      final entry = _entries[replacementIndex];
      entry
        ..notification = notification
        ..exiting = false;
      _scheduleAutoDismiss(entry);
      notifyListeners();
      return;
    }

    final entry = _NmtkNotificationEntry(
      id: _nextId++,
      notification: notification,
    );
    _entries.insert(0, entry);
    _scheduleAutoDismiss(entry);
    if (_entries.length > maxVisible) {
      _removeEntry(_entries.last);
    }
    notifyListeners();
  }

  /// Dismisses the live banner carrying [key]. No-op when nothing matches.
  void dismiss(Object? key) {
    if (key == null) return;
    final index = _entries.indexWhere(
      (_NmtkNotificationEntry entry) => entry.notification.key == key,
    );
    if (index != -1) {
      _beginExit(_entries[index]);
    }
  }

  /// Dismisses the banner with the given internal id (used by card widgets so
  /// close/action always target the exact card the user interacted with).
  void dismissEntry(int id) {
    final index = _entries.indexWhere(
      (_NmtkNotificationEntry entry) => entry.id == id,
    );
    if (index != -1) {
      _beginExit(_entries[index]);
    }
  }

  void _scheduleAutoDismiss(_NmtkNotificationEntry entry) {
    entry.timer?.cancel();
    final duration = entry.notification.duration;
    if (duration == null) return;
    entry.timer = Timer(duration, () => _beginExit(entry));
  }

  void _beginExit(_NmtkNotificationEntry entry) {
    if (_disposed || entry.exiting || !_entries.contains(entry)) return;
    entry
      ..exiting = true
      ..timer?.cancel()
      ..timer = Timer(exitDuration, () => _removeEntry(entry));
    notifyListeners();
  }

  void _removeEntry(_NmtkNotificationEntry entry) {
    if (_disposed) return;
    entry.timer?.cancel();
    if (!entry.actionTaken && !entry.dismissedCallbackSent) {
      entry.dismissedCallbackSent = true;
      entry.notification.onDismissed?.call();
    }
    _entries.remove(entry);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final entry in _entries) {
      entry.timer?.cancel();
    }
    _entries.clear();
    super.dispose();
  }
}

/// Hosts an app-wide stack of macOS-style notification banners pinned to the
/// top-right corner of the window.
///
/// Mount this once, as high as possible, wrapping the widget that owns the
/// navigator (e.g. in a `MaterialApp.builder`) so banners paint above every
/// route, dialog and snack bar. Banners are non-modal — the rest of the window
/// keeps receiving pointer events.
///
/// Callers push banners either through the returned scope controller:
///
/// ```dart
/// final controller = NmtkNotificationCenter.maybeControllerOf(context);
/// controller?.push(NmtkNotification(title: ..., message: ...));
/// ```
///
/// or through the [NmtkNotificationCenter.show] shorthand. Both are no-ops when
/// no host is mounted above `context`.
class NmtkNotificationCenter extends StatefulWidget {
  const NmtkNotificationCenter({
    super.key,
    required this.child,
    this.maxVisible = 5,
    this.edgePadding = const EdgeInsets.all(12),
    this.maxCardWidth = 380,
  });

  /// The widget the banners float above (normally the app's [Navigator]).
  final Widget child;

  /// Maximum number of banners shown at once.
  final int maxVisible;

  /// Insets between the banner stack and the window's top-right corner.
  final EdgeInsetsGeometry edgePadding;

  /// Preferred banner width; clamped to the window width minus [edgePadding].
  final double maxCardWidth;

  /// Returns the controller exposed above `context`, or `null` when no
  /// [NmtkNotificationCenter] host is mounted. Does not create a dependency.
  static NmtkNotificationCenterController? maybeControllerOf(
    BuildContext context,
  ) {
    final scope = context
        .getInheritedWidgetOfExactType<_NmtkNotificationCenterScope>();
    return scope?.controller;
  }

  /// Pushes [notification] onto the nearest host, or does nothing when no host
  /// is mounted above `context`.
  static void show(BuildContext context, NmtkNotification notification) {
    maybeControllerOf(context)?.push(notification);
  }

  @override
  State<NmtkNotificationCenter> createState() => _NmtkNotificationCenterState();
}

class _NmtkNotificationCenterState extends State<NmtkNotificationCenter> {
  late final NmtkNotificationCenterController _controller =
      NmtkNotificationCenterController(maxVisible: widget.maxVisible);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleNotificationsChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.exitDuration = NmtkShellTokens.of(context).fastMotion;
  }

  @override
  void dispose() {
    _controller.removeListener(_handleNotificationsChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleNotificationsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final media = MediaQuery.sizeOf(context);
    final horizontalPadding = widget.edgePadding.horizontal;
    final maxWidth = math.max(
      0.0,
      math.min(widget.maxCardWidth, media.width - horizontalPadding),
    );
    // SafeArea and [edgePadding] handle the window insets below; this only
    // bounds the scrollable so a tall stack never overflows the viewport.
    final maxHeight = math.max(0.0, media.height - widget.edgePadding.vertical);
    final entries = _controller._entries;

    return _NmtkNotificationCenterScope(
      controller: _controller,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (entries.isNotEmpty)
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: widget.edgePadding,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxWidth,
                      maxHeight: maxHeight,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < entries.length; i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            _NmtkNotificationBanner(
                              key: ValueKey<int>(entries[i].id),
                              entry: entries[i],
                              controller: _controller,
                              tokens: tokens,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NmtkNotificationCenterScope extends InheritedWidget {
  const _NmtkNotificationCenterScope({
    required this.controller,
    required super.child,
  });

  final NmtkNotificationCenterController controller;

  @override
  bool updateShouldNotify(_NmtkNotificationCenterScope oldWidget) =>
      controller != oldWidget.controller;
}

class _NmtkNotificationEntry {
  _NmtkNotificationEntry({required this.id, required this.notification});

  final int id;
  NmtkNotification notification;
  bool exiting = false;
  bool actionTaken = false;
  bool dismissedCallbackSent = false;
  Timer? timer;
}

IconData _defaultIconForTone(NmtkTone tone) {
  return switch (tone) {
    NmtkTone.neutral || NmtkTone.info => ZetaIcons.info_sharp,
    NmtkTone.success => ZetaIcons.check_circle_round,
    NmtkTone.warning => ZetaIcons.warning_outline,
    NmtkTone.danger => ZetaIcons.error_outline,
  };
}

class _NmtkNotificationBanner extends StatelessWidget {
  const _NmtkNotificationBanner({
    super.key,
    required this.entry,
    required this.controller,
    required this.tokens,
  });

  final _NmtkNotificationEntry entry;
  final NmtkNotificationCenterController controller;
  final NmtkShellTokens tokens;

  @override
  Widget build(BuildContext context) {
    final notification = entry.notification;
    final theme = Theme.of(context);
    final palette = resolveNmtkTonePalette(context, notification.tone);
    final icon = notification.icon ?? _defaultIconForTone(notification.tone);
    final textStyles = Zeta.of(context).textStyles;

    // Fade + slide the banner in from the right on first appearance.
    Widget surface = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: tokens.standardMotion,
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double t, Widget? child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(32 * (1 - t), 0),
            child: child,
          ),
        );
      },
      child: Material(
        color: palette.background,
        elevation: 6,
        shadowColor: theme.shadowColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          side: BorderSide(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: palette.foreground.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 20, color: palette.foreground),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.title,
                          style: textStyles.titleMedium.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (notification.message.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            notification.message,
                            style: textStyles.bodyMedium.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (notification.showCloseButton) ...[
                    const SizedBox(width: 4),
                    ZetaIconButton(
                      type: ZetaButtonType.subtle,
                      size: ZetaWidgetSize.small,
                      icon: ZetaIcons.close_sharp,
                      semanticLabel: 'Dismiss notification',
                      onPressed: () => controller.dismissEntry(entry.id),
                    ),
                  ],
                ],
              ),
              if (notification.action != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: ZetaButton(
                    type: ZetaButtonType.text,
                    size: ZetaWidgetSize.small,
                    label: notification.action!.label,
                    onPressed: () {
                      entry.actionTaken = true;
                      controller.dismissEntry(entry.id);
                      notification.action!.onPressed();
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    // Fade + slide the banner out while it is being dismissed.
    return AnimatedOpacity(
      opacity: entry.exiting ? 0 : 1,
      duration: controller.exitDuration,
      child: AnimatedSlide(
        offset: entry.exiting ? const Offset(0.06, 0) : Offset.zero,
        duration: controller.exitDuration,
        curve: Curves.easeIn,
        child: surface,
      ),
    );
  }
}
