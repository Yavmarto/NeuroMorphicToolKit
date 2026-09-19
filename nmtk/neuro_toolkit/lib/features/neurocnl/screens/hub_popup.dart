import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/hub_preview.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/hub_preview_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/neurohub_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_client.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/hub_artefact_detail_view.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/hub_explore_view.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/hub_popup_header.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/hub_profile_view.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/neurohub_sign_in_dialog.dart';

// Publishing a result now opens `showPublishResultsDialog` directly from the
// Review step (see `studio/hub/publish_results_dialog.dart`), so this popup
// only ever browses/profiles Hub content — no more share intents here.
enum HubPopupIntent { profile, workspaces }

Future<void> showHubPopup(
  BuildContext context, {
  HubPopupIntent intent = HubPopupIntent.profile,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  var session = container.read(neurohubSessionProvider);
  if (session.status == NeurohubSessionStatus.restoring) {
    await container.read(neurohubSessionProvider.notifier).waitForRestoration();
    session = container.read(neurohubSessionProvider);
  }
  if (session.isSignedIn) {
    try {
      await container.read(neurohubClientProvider).listWorkspaces();
    } on NeurohubException catch (error) {
      if (error.statusCode == 401) {
        await container
            .read(neurohubSessionProvider.notifier)
            .signOut(message: 'Your Neurohub sign-in expired. Sign in again.');
      }
    }
    session = container.read(neurohubSessionProvider);
  }
  if (!session.isSignedIn) {
    if (!context.mounted) return;
    final signedIn = await showNeurohubSignInDialog(context);
    if (!signedIn || !context.mounted) return;
  }
  if (!context.mounted) return;
  return showDialog<void>(
    context: context,
    builder: (context) => HubPopup(intent: intent),
  );
}

class HubPopup extends ConsumerStatefulWidget {
  const HubPopup({super.key, required this.intent});

  final HubPopupIntent intent;

  @override
  ConsumerState<HubPopup> createState() => _HubPopupState();
}

class _HubPopupState extends ConsumerState<HubPopup> {
  late _HubTab _tab;
  String _query = '';
  String? _selectedTag;
  HubArtefactKind? _kindFilter;
  bool _popularFirst = false;
  HubArtefactPreview? _selectedItem;

  @override
  void initState() {
    super.initState();
    _tab = widget.intent == HubPopupIntent.workspaces
        ? _HubTab.explore
        : _HubTab.profile;
    _kindFilter = widget.intent == HubPopupIntent.workspaces
        ? HubArtefactKind.workspace
        : null;
  }

  void _toggleVisibility(HubArtefactPreview item) {
    ref.read(hubArtefactPreviewsProvider.notifier).toggleVisibility(item.id);
    setState(() {
      _selectedItem = ref
          .read(hubArtefactPreviewsProvider)
          .firstWhere((candidate) => candidate.id == item.id);
    });
  }

  void _selectItem(HubArtefactPreview item) =>
      setState(() => _selectedItem = item);

  void _selectTag(String? tag) => setState(() {
    _selectedTag = tag;
    if (tag != null) _tab = _HubTab.explore;
  });

  void _clearFilters() => setState(() {
    _query = '';
    _kindFilter = null;
    _selectedTag = null;
  });

  void _openInStudioPreview() {
    NmtkSnackBars.info(
      context,
      'Workspace opening will be connected to the registry next.',
    );
  }

  void _runBenchmarkPreview() {
    NmtkSnackBars.success(
      context,
      'Benchmark run is ready to open in Results.',
    );
  }

  void _downloadNodePreview() {
    NmtkSnackBars.info(
      context,
      'Node download is ready for the local Hub preview.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = NmtkDialogSurface.isCompact(context);
    final tokens = NmtkShellTokens.of(context);
    final content = Material(
      color: tokens.shellBackground,
      child: SafeArea(
        child: Column(
          children: <Widget>[
            HubPopupHeader(
              showingDetail: _selectedItem != null,
              onBack: () => setState(() => _selectedItem = null),
              onClose: () => Navigator.of(context).pop(),
              navigation: SizedBox(
                width: compact ? double.infinity : 300,
                child: ZetaSegmentedControl<_HubTab>(
                  segments: const <ZetaButtonSegment<_HubTab>>[
                    ZetaButtonSegment(
                      value: _HubTab.profile,
                      child: Text('My Profile'),
                    ),
                    ZetaButtonSegment(
                      value: _HubTab.explore,
                      child: Text('Explore'),
                    ),
                  ],
                  selected: _tab,
                  onChanged: (tab) => setState(() {
                    _tab = tab;
                    _selectedItem = null;
                  }),
                ),
              ),
            ),
            Expanded(child: _content()),
          ],
        ),
      ),
    );
    if (compact) return Dialog.fullscreen(child: content);
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: SizedBox(width: 1120, height: 760, child: content),
    );
  }

  Widget _content() {
    final selected = _selectedItem;
    if (selected != null) {
      return HubArtefactDetailView(
        item: selected,
        selectedTag: _selectedTag,
        onTagSelected: _selectTag,
        onOpenInStudio: _openInStudioPreview,
        onRunBenchmark: _runBenchmarkPreview,
        onDownloadNode: _downloadNodePreview,
      );
    }
    final session = ref.watch(neurohubSessionProvider);
    if (session.isSignedIn) {
      final realWorkspacesAsync = ref.watch(neurohubWorkspacesProvider);
      return realWorkspacesAsync.when(
        data: (realWorkspaces) {
          final items = realWorkspaces
              .map(
                (w) => HubArtefactPreview(
                  id: '${w.owner}/${w.slug}',
                  title: w.displayName,
                  kind: HubArtefactKind.workspace,
                  description: w.description,
                  author: w.owner,
                  visibility: (w.permission == 'admin' || w.private)
                      ? HubVisibility.private
                      : HubVisibility.public,
                  updatedLabel: 'Recently',
                  recency: 5,
                  popularity: 10,
                  tags: w.tags,
                  rawWorkspace: w is NeurohubWorkspace ? w.workspace : null,
                  detail: HubArtefactDetail(
                    overview: w.description,
                    fields: const [],
                  ),
                ),
              )
              .toList();

          if (_tab == _HubTab.profile) {
            return HubProfileView(
              items: items,
              selectedTag: _selectedTag,
              onSelect: _selectItem,
              onTagSelected: _selectTag,
              onToggleVisibility: _toggleVisibility,
            );
          }
          final exploreItems = items
              .where(
                (w) =>
                    w.visibility == HubVisibility.public ||
                    !w.id.contains('gesture-model'),
              )
              .toList();
          return HubExploreView(
            items: exploreItems,
            query: _query,
            kindFilter: _kindFilter,
            selectedTag: _selectedTag,
            popularFirst: _popularFirst,
            onQueryChanged: (query) => setState(() => _query = query),
            onKindChanged: (kind) => setState(() => _kindFilter = kind),
            onTagSelected: _selectTag,
            onSortChanged: (popularFirst) =>
                setState(() => _popularFirst = popularFirst),
            onSelect: _selectItem,
            onClearFilters: _clearFilters,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
      );
    }

    final items = ref.watch(hubArtefactPreviewsProvider);
    if (_tab == _HubTab.profile) {
      return HubProfileView(
        items: items,
        selectedTag: _selectedTag,
        onSelect: _selectItem,
        onTagSelected: _selectTag,
        onToggleVisibility: _toggleVisibility,
      );
    }
    return HubExploreView(
      items: items,
      query: _query,
      kindFilter: _kindFilter,
      selectedTag: _selectedTag,
      popularFirst: _popularFirst,
      onQueryChanged: (query) => setState(() => _query = query),
      onKindChanged: (kind) => setState(() => _kindFilter = kind),
      onTagSelected: _selectTag,
      onSortChanged: (popularFirst) =>
          setState(() => _popularFirst = popularFirst),
      onSelect: _selectItem,
      onClearFilters: _clearFilters,
    );
  }
}

enum _HubTab { profile, explore }
