library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/providers/deploy_targets_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/shell_surface.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/support_level_badge.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_target_catalog/support.dart';

class CodegenSetupPane extends ConsumerWidget {
  const CodegenSetupPane({super.key, required this.target, required this.spec});

  final String target;
  final String spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textStyles = Zeta.of(context).textStyles;
    final label = targetLabel(target);
    final previewAsync = ref.watch(
      deployPreviewProvider((spec: spec, target: target)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Target code setup',
          style: textStyles.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        previewAsync.when(
          data: (preview) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SupportLevelBadge(level: preview.supportLevel),
              if (preview.ioError != null) ...[
                const SizedBox(height: 8),
                NeurocnlMessageList(
                  messages: [preview.ioError!],
                  tone: NmtkTone.danger,
                  icon: ZetaIcons.cancel_outline,
                ),
              ],
              if (preview.diagnostics.isNotEmpty) ...[
                const SizedBox(height: 8),
                NeurocnlMessageList(
                  messages: preview.diagnostics,
                  tone: NmtkTone.warning,
                  icon: ZetaIcons.warning_outline,
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Generated $label code preview',
                style: textStyles.titleSmall,
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(
                    NmtkShellTokens.of(context).radiusSm,
                  ),
                ),
                child: SelectableText(
                  preview.code,
                  style: const TextStyle(
                    fontFamily: AppTheme.monospaceFontFamily,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text(
            'Preview failed: $error',
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
