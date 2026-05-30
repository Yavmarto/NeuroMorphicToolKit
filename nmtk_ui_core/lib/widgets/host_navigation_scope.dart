import 'package:flutter/widgets.dart';

import 'package:nmtk_ui_core/models/host_navigation_models.dart';

class NmtkHostNavigationScope extends InheritedWidget {
  const NmtkHostNavigationScope({
    super.key,
    required this.navigator,
    required super.child,
  });

  final NmtkHostModuleNavigator navigator;

  static NmtkHostModuleNavigator? maybeNavigatorOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<NmtkHostNavigationScope>()
        ?.navigator;
  }

  static Future<bool> openModule(
    BuildContext context,
    NmtkHostNavigationRequest request,
  ) async {
    final navigator = maybeNavigatorOf(context);
    if (navigator == null) {
      return false;
    }
    return navigator(request);
  }

  @override
  bool updateShouldNotify(NmtkHostNavigationScope oldWidget) {
    return navigator != oldWidget.navigator;
  }
}
