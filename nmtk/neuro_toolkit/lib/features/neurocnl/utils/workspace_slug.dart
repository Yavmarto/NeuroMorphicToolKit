final RegExp _nonSlugChars = RegExp(r'[^a-z0-9]+');
final RegExp _edgeDashes = RegExp(r'^-+|-+$');

/// Turns a workspace name into a folder/URL-safe slug.
///
/// Same regex already duplicated across `run_step.dart`, `notebook_step.dart`,
/// `workspace_file_io.dart`, and others — this is the canonical version, used
/// by new code (server workspace sync) rather than adding a 6th copy.
String slugifyWorkspaceName(String name) => name
    .toLowerCase()
    .replaceAll(_nonSlugChars, '-')
    .replaceAll(_edgeDashes, '');
