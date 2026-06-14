import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/widgets/adaptive_layout.dart';

void main() {
  testWidgets('shows mobileBuilder when width < 600 (default breakpoint)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: NmtkAdaptiveLayout(
          mobileBuilder: _MobileStub.new,
          desktopBuilder: _DesktopStub.new,
        ),
      ),
    );
    expect(find.byType(_MobileStub), findsOneWidget);
    expect(find.byType(_DesktopStub), findsNothing);
  });

  testWidgets('shows desktopBuilder when width >= 600 (default breakpoint)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: NmtkAdaptiveLayout(
          mobileBuilder: _MobileStub.new,
          desktopBuilder: _DesktopStub.new,
        ),
      ),
    );
    expect(find.byType(_DesktopStub), findsOneWidget);
    expect(find.byType(_MobileStub), findsNothing);
  });

  testWidgets('custom breakpoint: 375 < 800 → mobile', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: NmtkAdaptiveLayout(
          breakpoint: 800,
          mobileBuilder: _MobileStub.new,
          desktopBuilder: _DesktopStub.new,
        ),
      ),
    );
    expect(find.byType(_MobileStub), findsOneWidget);
  });

  testWidgets('custom breakpoint: 1024 >= 800 → desktop', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: NmtkAdaptiveLayout(
          breakpoint: 800,
          mobileBuilder: _MobileStub.new,
          desktopBuilder: _DesktopStub.new,
        ),
      ),
    );
    expect(find.byType(_DesktopStub), findsOneWidget);
  });
}

class _MobileStub extends StatelessWidget {
  const _MobileStub(BuildContext context);
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _DesktopStub extends StatelessWidget {
  const _DesktopStub(BuildContext context);
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
