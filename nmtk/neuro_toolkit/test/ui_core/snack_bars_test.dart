import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'notification_center_test.dart';

void main() {
  testWidgets('NmtkSnackBars.success shows a success banner', (tester) async {
    final context = await pumpNotificationCenterHost(tester);

    NmtkSnackBars.success(context, 'Done');
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsOneWidget);
    expect(find.byIcon(ZetaIcons.check_circle_round), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('NmtkSnackBars.error shows a danger banner', (tester) async {
    final context = await pumpNotificationCenterHost(tester);

    NmtkSnackBars.error(context, 'Failed');
    await tester.pumpAndSettle();

    expect(find.text('Failed'), findsOneWidget);
    expect(find.byIcon(ZetaIcons.error_outline), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}
