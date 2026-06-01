import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

class _Host extends StatelessWidget {
  const _Host({required this.builder});
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      theme: NmtkCupertinoTheme.dark,
      home: CupertinoPageScaffold(child: Builder(builder: builder)),
    );
  }
}

void main() {
  testWidgets('NmtkSnackBars.success pumps a success-tone banner',
      (tester) async {
    await tester.pumpWidget(_Host(builder: (context) {
      return CupertinoButton(
        onPressed: () => NmtkSnackBars.success(context, 'Done'),
        child: const Text('trigger'),
      );
    }));
    await tester.tap(find.text('trigger'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('NmtkSnackBars.error pumps an error-tone banner',
      (tester) async {
    await tester.pumpWidget(_Host(builder: (context) {
      return CupertinoButton(
        onPressed: () => NmtkSnackBars.error(context, 'Failed'),
        child: const Text('trigger'),
      );
    }));
    await tester.tap(find.text('trigger'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Failed'), findsOneWidget);
  });

  testWidgets('NmtkSnackBars returns a handle that can dismiss early',
      (tester) async {
    NmtkToastHandle? handle;
    await tester.pumpWidget(_Host(builder: (context) {
      return CupertinoButton(
        onPressed: () {
          handle = NmtkSnackBars.info(
            context,
            'Heads up',
            duration: const Duration(seconds: 30),
          );
        },
        child: const Text('trigger'),
      );
    }));
    await tester.tap(find.text('trigger'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Heads up'), findsOneWidget);
    handle!.dismiss();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Heads up'), findsNothing);
  });
}
