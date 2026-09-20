part of 'mobile_scaffold.dart';

class _NmtkMobileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _NmtkMobileAppBar({
    required this.scheme,
    required this.showBackButton,
    required this.backTooltip,
    this.onBack,
    this.title,
  });

  final ColorScheme scheme;
  final bool showBackButton;
  final VoidCallback? onBack;
  final String? title;
  final String backTooltip;

  @override
  Size get preferredSize => const Size.fromHeight(64.0);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                if (showBackButton)
                  IconButton(
                    icon: Icon(ZetaIcons.arrow_back, color: scheme.onSurface),
                    iconSize: 24,
                    padding: const EdgeInsets.all(16),
                    onPressed: onBack,
                    tooltip: backTooltip,
                  ),

                if (title != null && title!.isNotEmpty) ...[
                  if (showBackButton) const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Zeta.of(context).textStyles.titleLarge.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
