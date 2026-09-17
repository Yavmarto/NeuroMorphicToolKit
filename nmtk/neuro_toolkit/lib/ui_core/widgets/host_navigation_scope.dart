import 'package:flutter/widgets.dart';

import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

class NmtkHostNavigationScope extends InheritedWidget {
  const NmtkHostNavigationScope({
    super.key,
    required this.navigator,
    required super.child,
  });

  final NmtkFeatureNavigator navigator;

  static NmtkFeatureNavigator? maybeNavigatorOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<NmtkHostNavigationScope>()
        ?.navigator;
  }

  static Future<bool> openModule(
    BuildContext context,
    NmtkFeatureNavigationRequest request,
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
