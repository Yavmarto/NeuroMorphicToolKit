import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_wgpu_renderer_plugin/nmtk_wgpu_renderer_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nmtk_wgpu_renderer_plugin');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'registerTexture':
          return 7;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('registerTexture forwards the pixel buffer pointer and returns the texture id', () async {
    final id = await NmtkWgpuRendererPlugin.registerTexture(0x1234);

    expect(id, 7);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'registerTexture');
    expect(calls.single.arguments, {'pixelBufferPtr': 0x1234});
  });

  test('unregisterTexture forwards the texture id', () async {
    await NmtkWgpuRendererPlugin.unregisterTexture(7);

    expect(calls.single.method, 'unregisterTexture');
    expect(calls.single.arguments, {'textureId': 7});
  });
}
