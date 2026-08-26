import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

void main() {
  testWidgets('openModule uses the nearest host navigator', (tester) async {
    NmtkFeatureNavigationRequest? receivedRequest;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: NmtkHostNavigationScope(
          navigator: (request) async {
            receivedRequest = request;
            return true;
          },
          child: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  NmtkHostNavigationScope.openModule(
                    context,
                    NmtkFeatureNavigationRequest(
                      moduleId: NmtkModuleId.neurochip,
                      deepLink: '/?import_network=abc123',
                    ),
                  );
                },
                child: const Text('Open Module'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Module'));
    await tester.pump();

    expect(receivedRequest, isNotNull);
    expect(receivedRequest!.moduleId, NmtkModuleId.neurochip);
    expect(receivedRequest!.deepLink, '/?import_network=abc123');
  });

  testWidgets('openModule returns false outside a host scope', (tester) async {
    var result = true;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                result = await NmtkHostNavigationScope.openModule(
                  context,
                  NmtkFeatureNavigationRequest(
                    moduleId: NmtkModuleId.neurochip,
                  ),
                );
              },
              child: const Text('Open Without Scope'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open Without Scope'));
    await tester.pump();

    expect(result, isFalse);
  });
}
