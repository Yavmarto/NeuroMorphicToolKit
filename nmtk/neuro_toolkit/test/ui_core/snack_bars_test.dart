import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

void main() {
  testWidgets('NmtkSnackBars.success uses healthyColor', (tester) async {
    late BuildContext context;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final snackBar = NmtkSnackBars.success(context, 'Done');
    final tokens = NmtkShellTokens.of(context);

    expect(snackBar.backgroundColor, tokens.healthyColor);
    expect(snackBar.showCloseIcon, isTrue);
  });

  testWidgets('NmtkSnackBars.error uses errorColor', (tester) async {
    late BuildContext context;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final snackBar = NmtkSnackBars.error(context, 'Failed');
    final tokens = NmtkShellTokens.of(context);

    expect(snackBar.backgroundColor, tokens.errorColor);
    expect(snackBar.showCloseIcon, isTrue);
  });
}
