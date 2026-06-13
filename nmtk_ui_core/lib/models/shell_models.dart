import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/widgets/tone.dart';

enum NmtkShellMode { command, studio, instrument }

enum NmtkShellReadinessState { opening, warmingUp, ready, degraded, error }

enum NmtkWorkspaceVisualState { active, idle, starting, degraded, error }

class NmtkShellStatusSpec {
  final String label;
  final NmtkTone tone;
  final IconData? icon;
  final NmtkShellReadinessState? readinessState;
  final String? detailText;
  final String? semanticsLabel;

  const NmtkShellStatusSpec({
    required this.label,
    required this.tone,
    this.icon,
    this.readinessState,
    this.detailText,
    this.semanticsLabel,
  });

  factory NmtkShellStatusSpec.fromReadinessState(
    NmtkShellReadinessState state, {
    String? detailText,
    String? semanticsLabel,
  }) {
    return switch (state) {
      NmtkShellReadinessState.opening => NmtkShellStatusSpec(
        label: 'Opening',
        tone: NmtkTone.info,
        icon: Icons.door_front_door_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
        readinessState: state,
        detailText: detailText,
        semanticsLabel: semanticsLabel,
      ),
      NmtkShellReadinessState.warmingUp => NmtkShellStatusSpec(
        label: 'Warming Up',
        tone: NmtkTone.warning,
        icon: Icons.hourglass_top_rounded, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
        readinessState: state,
        detailText: detailText,
        semanticsLabel: semanticsLabel,
      ),
      NmtkShellReadinessState.ready => NmtkShellStatusSpec(
        label: 'Ready',
        tone: NmtkTone.success,
        icon: ZetaIcons.check_circle_outline,
        readinessState: state,
        detailText: detailText,
        semanticsLabel: semanticsLabel,
      ),
      NmtkShellReadinessState.degraded => NmtkShellStatusSpec(
        label: 'Degraded',
        tone: NmtkTone.warning,
        icon: ZetaIcons.warning_outline,
        readinessState: state,
        detailText: detailText,
        semanticsLabel: semanticsLabel,
      ),
      NmtkShellReadinessState.error => NmtkShellStatusSpec(
        label: 'Error',
        tone: NmtkTone.danger,
        icon: ZetaIcons.error_outline,
        readinessState: state,
        detailText: detailText,
        semanticsLabel: semanticsLabel,
      ),
    };
  }
}

class NmtkWorkspaceChipData {
  final String id;
  final String label;
  final IconData icon;
  final NmtkWorkspaceVisualState state;
  final bool pinned;
  final bool closable;
  final String? statusText;
  final int? badgeCount;
  final String? semanticsLabel;

  const NmtkWorkspaceChipData({
    required this.id,
    required this.label,
    required this.icon,
    this.state = NmtkWorkspaceVisualState.idle,
    this.pinned = false,
    this.closable = true,
    this.statusText,
    this.badgeCount,
    this.semanticsLabel,
  });
}

class NmtkTopAppBarAction {
  final IconData icon;
  final String? label;
  final String tooltip;
  final String? semanticsLabel;
  final bool selected;
  final VoidCallback onPressed;

  const NmtkTopAppBarAction({
    required this.icon,
    this.label,
    required this.tooltip,
    required this.onPressed,
    this.semanticsLabel,
    this.selected = false,
  });
}
