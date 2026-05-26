import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'tone.dart';

/// Maps an [NmtkTone] to its Zeta [ZetaWidgetStatus] equivalent.
///
/// Mirror the mapping in `status_badge.dart` so banners and badges agree.
ZetaWidgetStatus nmtkToneToZetaWidgetStatus(NmtkTone tone) {
  return switch (tone) {
    NmtkTone.neutral => ZetaWidgetStatus.info,
    NmtkTone.info => ZetaWidgetStatus.info,
    NmtkTone.success => ZetaWidgetStatus.positive,
    NmtkTone.warning => ZetaWidgetStatus.warning,
    NmtkTone.danger => ZetaWidgetStatus.negative,
  };
}

/// A thin NMTK-tone wrapper around Zeta's in-page banner primitive.
///
/// Use [NmtkStatusBanner] for "important, succinct status messages" (per Zeta's
/// own description of [ZetaInPageBanner]) — e.g. "All invariants passed",
/// "Backend Support: faithful", "Akida — runtime mapped successfully", or an
/// inline error.
///
/// This deliberately bypasses [NmtkSurfaceCard] so that banners never live
/// inside a heavy card frame. The whole point of the migration: status content
/// uses the dedicated banner primitive, not a generic section card.
class NmtkStatusBanner extends StatelessWidget {
  const NmtkStatusBanner({
    super.key,
    required this.title,
    this.content,
    this.tone = NmtkTone.info,
    this.icon,
    this.actions = const [],
    this.canClose = false,
    this.onClose,
  });

  /// Title of the banner, displayed at the top.
  final String title;

  /// Body content of the banner. When null, a 0 px placeholder renders so the
  /// banner is title-only.
  final Widget? content;

  /// Tone of the banner. Mapped to [ZetaWidgetStatus] via
  /// [nmtkToneToZetaWidgetStatus].
  final NmtkTone tone;

  /// Optional custom icon. Defaults to the Zeta status default for the tone.
  final IconData? icon;

  /// Optional action buttons to render at the bottom of the banner.
  final List<ZetaButton> actions;

  /// When true, the banner shows a close affordance and calls [onClose] when
  /// tapped. Defaults to false — most NMTK status surfaces are persistent.
  final bool canClose;

  /// Called when the close affordance is tapped. Only used when [canClose] is
  /// true; ignored otherwise.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return ZetaInPageBanner(
      title: title,
      content: content ?? const SizedBox.shrink(),
      status: nmtkToneToZetaWidgetStatus(tone),
      customIcon: icon,
      actions: actions,
      onClose: canClose ? onClose : null,
    );
  }
}
