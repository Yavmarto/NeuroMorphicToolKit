import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/services/platform_helper_stub.dart' as platform;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'getApplicationDocumentsDirectory') {
              return '/tmp';
            }
            return null;
          },
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter/platform', JSONMethodCodec()),
          (MethodCall methodCall) async {
            if (methodCall.method == 'Clipboard.setData') {
              return null;
            }
            if (methodCall.method == 'Clipboard.getData') {
              return {'text': 'mocked_clipboard'};
            }
            return null;
          },
        );
  });

  group('Platform Helper Stub', () {
    test('getOrigin returns null', () {
      expect(platform.getOrigin(), isNull);
    });

    test('openUrl returns false on native platforms', () async {
      expect(await platform.openUrl('http://localhost:8001'), isFalse);
    });

    test('copyToClipboard completes', () async {
      await expectLater(platform.copyToClipboard('test text'), completes);
    });

    test(
      'downloadFile falls back to the native file adapter save flow',
      () async {
        final result = await platform.downloadFile(
          'test.txt',
          'content',
          'text/plain',
        );
        expect(result.needsFallback, isTrue);
        expect(result.path, isNull);
      },
    );
  });
}
