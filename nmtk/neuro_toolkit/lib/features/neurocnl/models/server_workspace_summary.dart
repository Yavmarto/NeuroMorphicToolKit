/// Metadata for a workspace saved on the server (no config blob) — used by
/// the "Load from server" picker's list view.
class ServerWorkspaceSummary {
  final String slug;
  final String name;
  final String updatedAt;

  const ServerWorkspaceSummary({
    required this.slug,
    required this.name,
    required this.updatedAt,
  });

  factory ServerWorkspaceSummary.fromJson(Map<String, dynamic> json) =>
      ServerWorkspaceSummary(
        slug: json['slug'] as String,
        name: json['name'] as String,
        updatedAt: json['updated_at'] as String,
      );
}
