import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Mounts a [NmtkNotificationCenter] around a probe [Builder] and returns a
/// [BuildContext] that sits inside the scope, so tests can push banners the
/// same way app code does.
Future<BuildContext> pumpNotificationCenterHost(
  WidgetTester tester, {
  Widget? content,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: NmtkNotificationCenter(
        maxVisible: 3,
        child: Builder(
          builder: (ctx) =>
              content ??
              const Scaffold(body: Center(child: Text('host content'))),
        ),
      ),
    ),
  );
  return tester.element(find.text('host content'));
}

void main() {
  testWidgets('shows a banner with title, message and icon', (tester) async {
    final context = await pumpNotificationCenterHost(tester);

    NmtkNotificationCenter.show(
      context,
      const NmtkNotification(
        title: 'Connection Problem',
        message: 'NeuroStudio cannot reach the selected backend.',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connection Problem'), findsOneWidget);
    expect(
      find.text('NeuroStudio cannot reach the selected backend.'),
      findsOneWidget,
    );
    expect(find.byIcon(ZetaIcons.info_sharp), findsOneWidget);
    expect(find.text('host content'), findsOneWidget);
  });

  testWidgets('close button dismisses the banner', (tester) async {
    final context = await pumpNotificationCenterHost(tester);

    NmtkNotificationCenter.show(
      context,
      const NmtkNotification(
        title: 'Connection Problem',
        message: 'A message.',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connection Problem'), findsOneWidget);

    await tester.tap(find.byIcon(ZetaIcons.close_sharp));
    await tester.pumpAndSettle();

    expect(find.text('Connection Problem'), findsNothing);
  });

  testWidgets('auto-dismisses after its duration', (tester) async {
    final context = await pumpNotificationCenterHost(tester);

    NmtkNotificationCenter.show(
      context,
      const NmtkNotification(
        title: 'Transient',
        message: 'Auto-dismiss me.',
        duration: Duration(milliseconds: 300),
      ),
    );
    await tester.pump();
    expect(find.text('Transient'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('Transient'), findsNothing);
  });

  testWidgets('stacks distinct notifications', (tester) async {
    final context = await pumpNotificationCenterHost(tester);

    NmtkNotificationCenter.show(
      context,
      const NmtkNotification(key: 'a', title: 'First', message: 'One.'),
    );
    NmtkNotificationCenter.show(
      context,
      const NmtkNotification(key: 'b', title: 'Second', message: 'Two.'),
    );
    await tester.pumpAndSettle();

    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.byIcon(ZetaIcons.close_sharp), findsNWidgets(2));
  });

  testWidgets('coalesces repeat pushes with the same key', (tester) async {
    final context = await pumpNotificationCenterHost(tester);

    NmtkNotificationCenter.show(
      context,
      const NmtkNotification(
        key: 'hosted-error',
        title: 'Connection Problem',
        message: 'First report.',
      ),
    );
    NmtkNotificationCenter.show(
      context,
      const NmtkNotification(
        key: 'hosted-error',
        title: 'Connection Problem',
        message: 'Second report.',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(ZetaIcons.close_sharp), findsOneWidget);
    expect(find.text('First report.'), findsNothing);
    expect(find.text('Second report.'), findsOneWidget);
  });

  testWidgets('action button runs the callback and dismisses the banner', (
    tester,
  ) async {
    final context = await pumpNotificationCenterHost(tester);
    var opened = 0;

    NmtkNotificationCenter.show(
      context,
      NmtkNotification(
        key: 'setup',
        title: 'Authentication Problem',
        message: 'Please set up your backend.',
        action: NmtkNotificationAction(
          label: 'Backend Setup',
          onPressed: () => opened++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Backend Setup'), findsOneWidget);
    await tester.tap(find.text('Backend Setup'));
    await tester.pumpAndSettle();

    expect(opened, 1);
    expect(find.text('Backend Setup'), findsNothing);
    expect(find.text('Authentication Problem'), findsNothing);
  });

  testWidgets('show is a no-op when no host is mounted', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('bare host'))),
      ),
    );

    final element = tester.element(find.text('bare host'));
    expect(NmtkNotificationCenter.maybeControllerOf(element), isNull);

    NmtkNotificationCenter.show(
      element,
      const NmtkNotification(title: 'Never shown', message: 'No host.'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Never shown'), findsNothing);
  });
}
