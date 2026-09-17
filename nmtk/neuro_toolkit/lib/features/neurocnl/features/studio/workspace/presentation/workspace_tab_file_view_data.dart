/// Immutable data rendered for one workspace tab.
class WorkspaceTabFileViewData {
  const WorkspaceTabFileViewData({
    required this.id,
    required this.name,
    required this.dirty,
  });

  final String id;
  final String name;
  final bool dirty;

  @override
  bool operator ==(Object other) {
    return other is WorkspaceTabFileViewData &&
        other.id == id &&
        other.name == name &&
        other.dirty == dirty;
  }

  @override
  int get hashCode => Object.hash(id, name, dirty);
}
