import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

class MujocoStreamView extends StatelessWidget {
  final String? streamUrl;

  const MujocoStreamView({super.key, this.streamUrl});

  String get _resolvedStreamUrl => streamUrl ?? '';

  @override
  Widget build(BuildContext context) {
    final resolvedStreamUrl = _resolvedStreamUrl;
    if (resolvedStreamUrl.isEmpty) {
      return const _UnavailableView(
        message: 'No MuJoCo stream URL configured.',
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            resolvedStreamUrl,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _UnavailableView(
              message: 'Stream unavailable at $resolvedStreamUrl',
            ),
            loadingBuilder: (context, child, progress) {
              if (progress == null) {
                return child;
              }
              return const _LoadingView();
            },
          ),
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusChip),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.stream,
                    size: 14,
                    color: Zeta.of(context).colors.mainInverse,
                  ), // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                  const SizedBox(width: 6),
                  Text(
                    'MJPEG stream',
                    style: Zeta.of(context).textStyles.labelSmall.copyWith(
                      color: Zeta.of(context).colors.mainInverse,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        border: Border.all(color: AppTheme.border),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 12),
            Text(
              'Connecting to MuJoCo stream…',
              style: Zeta.of(context).textStyles.bodyXSmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnavailableView extends StatelessWidget {
  final String message;

  const _UnavailableView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        border: Border.all(color: AppTheme.border),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                ZetaIcons.video_off,
                size: 48,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                'Simulation stream unavailable',
                style: Zeta.of(context).textStyles.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Zeta.of(context).textStyles.bodyXSmall.copyWith(
                  color: AppTheme.synComment,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
