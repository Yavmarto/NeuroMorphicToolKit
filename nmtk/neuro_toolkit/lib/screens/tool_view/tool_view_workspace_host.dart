import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What [ToolViewWorkspaceController] needs from its owning widget state:
/// rebuild scheduling and access to the widget's [BuildContext]/[WidgetRef].
abstract class ToolViewWorkspaceHost {
  bool get mounted;
  BuildContext get context;
  WidgetRef get ref;
  void rebuild(VoidCallback fn);
}
