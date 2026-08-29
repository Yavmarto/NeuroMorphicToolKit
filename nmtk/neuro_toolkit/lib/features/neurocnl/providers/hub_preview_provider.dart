import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/models/hub_preview.dart';

/// Mock in-memory store for Hub artefacts. NeuroHub's real publish endpoint
/// isn't wired up yet, so publishing writes here instead — the Hub popup and
/// profile read from this provider rather than the static [kHubPreviewArtefacts]
/// list directly, so a published workspace shows up immediately under
/// "My Profile" for the rest of the session.
final hubArtefactPreviewsProvider =
    NotifierProvider<HubArtefactPreviewsNotifier, List<HubArtefactPreview>>(
      HubArtefactPreviewsNotifier.new,
    );

class HubArtefactPreviewsNotifier extends Notifier<List<HubArtefactPreview>> {
  @override
  List<HubArtefactPreview> build() =>
      List<HubArtefactPreview>.of(kHubPreviewArtefacts);

  void toggleVisibility(String id) => state = state
      .map(
        (item) => item.id == id
            ? item.copyWith(
                visibility: item.visibility == HubVisibility.public
                    ? HubVisibility.private
                    : HubVisibility.public,
              )
            : item,
      )
      .toList();

  /// Adds a published workspace to the current user's profile.
  void addWorkspace({
    required String title,
    required String description,
    required HubVisibility visibility,
    required List<String> tags,
    required HubArtefactDetail detail,
    String? metric,
  }) {
    final topRecency = state.isEmpty
        ? 0
        : state.map((item) => item.recency).reduce((a, b) => a > b ? a : b);
    final item = HubArtefactPreview(
      id: 'published-${state.length}-${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      kind: HubArtefactKind.workspace,
      description: description,
      author: kHubCurrentUserName,
      visibility: visibility,
      updatedLabel: 'Updated just now',
      recency: topRecency + 1,
      popularity: 0,
      tags: tags,
      metric: metric,
      detail: detail,
    );
    state = <HubArtefactPreview>[item, ...state];
  }
}
