/// Neurohub frontend package.
///
/// Owns the module's Flutter UI (currently the 'Connect GitHub' OAuth device
/// flow screen). The launcher imports this package via `path:` and embeds
/// [GithubConnectScreen] inside its themed surface.
library;

export 'src/github_connect_screen.dart';
export 'src/github_connect_theme.dart';
export 'src/github_device_flow_client.dart';
export 'src/github_link_launcher.dart';
export 'src/github_token_storage.dart';
