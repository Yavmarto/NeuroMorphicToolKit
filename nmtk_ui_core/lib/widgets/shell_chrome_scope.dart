import 'package:flutter/widgets.dart';

/// Marker [InheritedWidget] inserted by [NmtkMobileScaffold] at the root of
/// its subtree.
///
/// [NmtkDesktopScaffold] checks for this widget before adding its own mobile
/// scaffold wrapper: if an ancestor already injected shell chrome, it passes
/// the child through unchanged rather than creating a second
/// [NmtkMobileScaffold] (which would produce double AppBar + double
/// BottomNavigationBar on narrow screens).
class NmtkShellChromeScope extends InheritedWidget {
  const NmtkShellChromeScope({super.key, required super.child});

  /// Returns `true` when [context] is inside a [NmtkShellChromeScope],
  /// i.e. the nearest ancestor [NmtkMobileScaffold] has already contributed
  /// its Scaffold chrome.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NmtkShellChromeScope>() !=
      null;

  @override
  bool updateShouldNotify(NmtkShellChromeScope _) => false;
}
