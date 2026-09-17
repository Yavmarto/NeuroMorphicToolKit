import 'package:url_launcher/url_launcher.dart';

/// Opens the verification URI in the user's browser.
///
/// Abstracted so widget tests can assert the opened URL without launching a
/// real browser.
abstract class GithubLinkLauncher {
  Future<bool> open(String url);
}

/// Default [GithubLinkLauncher] backed by the `url_launcher` plugin.
class PlatformGithubLinkLauncher implements GithubLinkLauncher {
  const PlatformGithubLinkLauncher();

  @override
  Future<bool> open(String url) async {
    final uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
