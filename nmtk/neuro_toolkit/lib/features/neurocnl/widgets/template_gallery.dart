import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/models/template.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/native_file_adapter_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/template_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/file_adapter.dart';
import 'package:neuro_toolkit/features/neurocnl/services/template_load_guard.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/loading_shimmer.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';

import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

/// Template gallery dialog showing available CNL spec templates.
///
/// Implements Epic 5: Template Gallery — searchable grid of template cards.
class TemplateGallery extends ConsumerStatefulWidget {
  const TemplateGallery({
    super.key,
    this.embedded = false,
    this.onClose,
    this.onTemplateLoaded,
  });

  final bool embedded;
  final VoidCallback? onClose;
  final VoidCallback? onTemplateLoaded;

  /// Show the template gallery as a dialog.
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppTheme.background,
        shape: RoundedRectangleBorder(
          borderRadius: NmtkDesignTokens.dialogShape,
          side: const BorderSide(color: AppTheme.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
          child: const TemplateGallery(),
        ),
      ),
    );
  }

  @override
  ConsumerState<TemplateGallery> createState() => _TemplateGalleryState();
}

class _TemplateGalleryState extends ConsumerState<TemplateGallery> {
  bool _ignoreDirty = false;
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(templateProvider);
    final activeFile = ref.watch(
      workspaceProvider.select((workspace) => workspace.activeFile),
    );
    final isDirty = activeFile?.dirty ?? false;
    final l10n = AppLocalizations.of(context);

    final grid = templatesAsync.when(
      loading: () => GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.6,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: 4,
        itemBuilder: (_, _) => const LoadingShimmer(
          width: double.infinity,
          height: double.infinity,
          borderRadius: 12,
        ),
      ),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ZetaIcons.cloud_off,
              size: 48,
              color: AppTheme.errorColorOf(context),
            ),
            const SizedBox(height: 8),
            const Text(
              'Could not load templates.\nIs the backend running?',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            ZetaButton.outline(
              leadingIcon: ZetaIcons.refresh,
              label: l10n?.retry ?? 'Retry',
              onPressed: () => ref.read(templateProvider.notifier).fetch(),
            ),
          ],
        ),
      ),
      data: (templates) {
        final query = _searchController.text.toLowerCase();
        final filtered = templates.where((t) {
          final matchesSearch =
              t.name.toLowerCase().contains(query) ||
              t.description.toLowerCase().contains(query) ||
              t.tags.any((tag) => tag.toLowerCase().contains(query));
          final matchesCategory =
              _selectedCategory == 'All' || t.category == _selectedCategory;
          return matchesSearch && matchesCategory;
        }).toList();

        if (filtered.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(ZetaIcons.search, size: 48, color: AppTheme.textSecondary),
                SizedBox(height: 8),
                Text(
                  'No templates match your filters.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            return _TemplateCard(
              template: filtered[index],
              closeOnSelect: !widget.embedded,
              onTemplateLoaded: widget.onTemplateLoaded,
            );
          },
        );
      },
    );

    if (widget.embedded) {
      // zeta-card-reduction Task 10: NeurocnlSectionCard → NmtkSection.
      // The legacy section card supported `expandChild: true` (a
      // surface-card-only feature). NmtkSection has a min-sized inner
      // Column, so to keep the grid filling the embedded host's height
      // we compose NmtkSectionHeader + Expanded(child: grid) explicitly.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NmtkSectionHeader(
            title: l10n?.templateGallery ?? 'Template Gallery',
            subtitle:
                l10n?.chooseTemplate ?? 'Choose a template to get started.',
            trailing: widget.onClose == null
                ? null
                : IconButton(
                    icon: const Icon(
                      ZetaIcons.close,
                      color: AppTheme.textSecondary,
                    ),
                    tooltip: l10n?.close ?? 'Close',
                    onPressed: widget.onClose,
                  ),
          ),
          const SizedBox(height: 12),
          Expanded(child: grid),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                color: AppTheme.primary,
                size: 24,
              ), // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              const SizedBox(width: 8),
              Text(
                l10n?.templateGallery ?? 'Template Gallery',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(
                  ZetaIcons.close,
                  color: AppTheme.textSecondary,
                ),
                tooltip: l10n?.close ?? 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n?.chooseTemplate ?? 'Choose a template to get started.',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // Search Bar
          NmtkTextInput(
            controller: _searchController,
            onChange: (_) => setState(() {}),
            hintText: 'Search templates...',
            prefix: const Icon(ZetaIcons.search, size: 18),
          ),
          const SizedBox(height: 12),

          // Category chips only render once template data is available.
          templatesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (templates) {
              final categories = [
                'All',
                ...templates.map((template) => template.category).toSet(),
              ];
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: categories.map((cat) {
                    final isSelected = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      // Allowed: legacy filter chip row — pending phase-2 migration.
                      child: ChoiceChip(
                        label: Text(cat),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedCategory = cat);
                          }
                        },
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        selectedColor: AppTheme.primary,
                        backgroundColor: AppTheme.surfaceVariant,
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusLg),
                        ),
                        showCheckmark: false,
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          if (isDirty && !_ignoreDirty) ...[
            // Allowed: single-topic surface — see governance.
            NmtkSurfaceCard(
              tone: NmtkTone.warning,
              title: 'Unsaved Changes',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The active file "${activeFile?.name}" has unsaved changes. Applying a template will overwrite these changes.',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ZetaButton.text(
                        onPressed: () async {
                          if (activeFile != null) {
                            final fileName = activeFile.isUntitled
                                ? 'spec.cnl'
                                : activeFile.name;
                            final suggestedName = fileName.endsWith('.cnl')
                                ? fileName
                                : '$fileName.cnl';
                            final result = await ref
                                .read(nativeFileAdapterProvider)
                                .saveTextFile(
                                  suggestedName: suggestedName,
                                  contents:
                                      activeFile.canonicalDocument?.cnlText ??
                                      '',
                                );
                            if (!context.mounted) {
                              return;
                            }
                            if (result.outcome == SaveOutcome.saved) {
                              ref
                                  .read(workspaceProvider.notifier)
                                  .markActiveFileSavedAs(
                                    name:
                                        _fileNameFromPath(result.path) ??
                                        suggestedName,
                                    path: result.path,
                                  );
                            } else if (result.outcome == SaveOutcome.failed) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                NmtkSnackBars.error(
                                  context,
                                  result.message ?? 'File save failed.',
                                ),
                              );
                            }
                          }
                        },
                        label: 'Save Active File',
                      ),
                      const SizedBox(width: 8),
                      ZetaButton.text(
                        onPressed: () => setState(() => _ignoreDirty = true),
                        label: 'Apply Anyway',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Templates grid
          Expanded(child: grid),
        ],
      ),
    );
  }

  String? _fileNameFromPath(String? path) {
    if (path == null || path.isEmpty) {
      return null;
    }
    final normalized = path.replaceAll('\\', '/');
    return normalized.split('/').last;
  }
}

class _TemplateCard extends ConsumerWidget {
  final CnlTemplate template;
  final bool closeOnSelect;
  final VoidCallback? onTemplateLoaded;

  const _TemplateCard({
    required this.template,
    required this.closeOnSelect,
    this.onTemplateLoaded,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: 'Template: ${template.name}. ${template.description}',
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
          border: Border.all(color: AppTheme.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
          onTap: () => _loadTemplate(context, ref),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        template.name,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _DifficultyBadge(difficulty: template.difficulty),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    template.description,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: template.tags.take(3).map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 10,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    if (!template.supportsTarget('lava_sim'))
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Tooltip(
                          message:
                              'This template uses node types not supported by Lava '
                              '(e.g. STDP, STP, neuromodulation). Run with SNNTorch.',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                ZetaIcons.warning_outline,
                                size: 12,
                                color: NmtkShellTokens.of(context).warningColor,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                'SNNTorch only',
                                style: TextStyle(
                                  color: NmtkShellTokens.of(
                                    context,
                                  ).warningColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                    const Icon(
                      ZetaIcons.arrow_forward,
                      size: 12,
                      color: AppTheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadTemplate(BuildContext context, WidgetRef ref) async {
    final shouldReplace = await confirmTemplateReplacement(
      context,
      ref,
      template,
    );
    if (!shouldReplace || !context.mounted) {
      return;
    }

    await applyTemplateToWorkspace(ref, template);
    if (!context.mounted) {
      return;
    }
    onTemplateLoaded?.call();
    if (closeOnSelect) {
      Navigator.of(context).pop();
    }
  }
}

class _DifficultyBadge extends StatelessWidget {
  final String difficulty;

  const _DifficultyBadge({required this.difficulty});

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    Color color;
    switch (difficulty) {
      case 'beginner':
        color = AppTheme.success;
        break;
      case 'intermediate':
        color = tokens.warningColor;
        break;
      case 'advanced':
        color = AppTheme.error;
        break;
      default:
        color = AppTheme.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        difficulty,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
