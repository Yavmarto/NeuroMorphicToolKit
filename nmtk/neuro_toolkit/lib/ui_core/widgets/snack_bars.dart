import 'package:flutter/material.dart';

import 'package:neuro_toolkit/ui_core/widgets/notification_center.dart';
import 'package:neuro_toolkit/ui_core/widgets/tone.dart';

/// Top-right notification helpers. Replaces the old bottom [SnackBar] surface.
class NmtkSnackBars {
  NmtkSnackBars._();

  static const Duration _defaultSuccessDuration = Duration(seconds: 4);
  static const Duration _defaultErrorDuration = Duration(seconds: 6);
  static const Duration _defaultInfoDuration = Duration(seconds: 4);
  static const Duration _defaultWarningDuration = Duration(seconds: 5);

  /// Shows a banner with [message] as the headline.
  static void show(
    BuildContext context,
    String message, {
    NmtkTone tone = NmtkTone.neutral,
    NmtkNotificationAction? action,
    Duration? duration,
    Object? key,
    VoidCallback? onDismissed,
  }) {
    final resolvedDuration = duration ??
        (action == null ? _defaultDurationForTone(tone) : null);
    NmtkNotificationCenter.show(
      context,
      NmtkNotification(
        key: key,
        title: message,
        message: '',
        tone: tone,
        action: action,
        duration: resolvedDuration,
        onDismissed: onDismissed,
      ),
    );
  }

  static void success(
    BuildContext context,
    String message, {
    NmtkNotificationAction? action,
    Duration? duration,
    Object? key,
    VoidCallback? onDismissed,
  }) {
    show(
      context,
      message,
      tone: NmtkTone.success,
      action: action,
      duration: duration,
      key: key,
      onDismissed: onDismissed,
    );
  }

  static void error(
    BuildContext context,
    String message, {
    NmtkNotificationAction? action,
    Duration? duration,
    Object? key,
    VoidCallback? onDismissed,
  }) {
    show(
      context,
      message,
      tone: NmtkTone.danger,
      action: action,
      duration: duration ?? (action == null ? _defaultErrorDuration : null),
      key: key,
      onDismissed: onDismissed,
    );
  }

  static void info(
    BuildContext context,
    String message, {
    NmtkNotificationAction? action,
    Duration? duration,
    Object? key,
    VoidCallback? onDismissed,
  }) {
    show(
      context,
      message,
      tone: NmtkTone.info,
      action: action,
      duration: duration,
      key: key,
      onDismissed: onDismissed,
    );
  }

  static void warning(
    BuildContext context,
    String message, {
    NmtkNotificationAction? action,
    Duration? duration,
    Object? key,
    VoidCallback? onDismissed,
  }) {
    show(
      context,
      message,
      tone: NmtkTone.warning,
      action: action,
      duration: duration,
      key: key,
      onDismissed: onDismissed,
    );
  }

  static Duration _defaultDurationForTone(NmtkTone tone) {
    return switch (tone) {
      NmtkTone.success => _defaultSuccessDuration,
      NmtkTone.danger => _defaultErrorDuration,
      NmtkTone.warning => _defaultWarningDuration,
      NmtkTone.neutral || NmtkTone.info => _defaultInfoDuration,
    };
  }
}
