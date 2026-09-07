import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The three baseline mobile viewports every screen is checked against
/// (CEL-73). devicePixelRatio is fixed at 1.0 so overflow px in failures
/// map directly to logical pixels.
const List<Size> kMobileTestViewports = <Size>[
  Size(360, 640), // common small Android
  Size(390, 844), // iPhone 12/13/14
  Size(414, 896), // iPhone 11 / XR
];

/// Pumps [build] at each of [kMobileTestViewports] as its own `testWidgets`
/// case and fails the test if layout throws a RenderFlex overflow
/// ("... overflowed by Npx ...").
///
/// [knownOverflows] marks a specific viewport as an already-known baseline
/// overflow that isn't being fixed here: pass the viewport's [Size] and a
/// reason string (e.g. an owning child-issue id and the overflow amount).
/// That viewport's case is skipped rather than gating the suite; every other
/// viewport still gates for real.
///
/// [settleDuration] is for screens that keep an indeterminate animation
/// alive (e.g. a loading spinner) where `pumpAndSettle` never converges —
/// pass a bounded duration to pump for instead of settling.
Future<void> testMobileViewports(
  String name,
  WidgetBuilder build, {
  Map<Size, String> knownOverflows = const <Size, String>{},
  Duration? settleDuration,
}) async {
  for (final size in kMobileTestViewports) {
    final skipReason = knownOverflows[size];
    testWidgets(
      '$name @ ${size.width.toInt()}x${size.height.toInt()}'
      '${skipReason != null ? ' (skipped: $skipReason)' : ''}',
      skip: skipReason != null,
      (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final originalOnError = FlutterError.onError;
        final overflows = <String>[];
        FlutterError.onError = (FlutterErrorDetails details) {
          final message = details.exceptionAsString();
          if (message.contains('overflowed by')) {
            overflows.add(message);
            return;
          }
          originalOnError?.call(details);
        };

        try {
          await tester.pumpWidget(
            Builder(builder: (context) => build(context)),
          );
          if (settleDuration != null) {
            await tester.pump();
            await tester.pump(settleDuration);
          } else {
            await tester.pumpAndSettle();
          }
        } finally {
          FlutterError.onError = originalOnError;
        }

        expect(
          overflows,
          isEmpty,
          reason:
              'RenderFlex overflow at ${size.width.toInt()}x'
              '${size.height.toInt()}:\n${overflows.join('\n')}',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
