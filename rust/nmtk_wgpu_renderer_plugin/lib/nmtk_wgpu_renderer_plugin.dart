import 'package:flutter/services.dart';

/// Thin wrapper around the macOS method channel that registers a native
/// `CVPixelBuffer` (produced by the nmtk_wgpu Rust renderer) as a Flutter
/// [Texture]. Registering a [Texture] against the embedder's texture
/// registry isn't reachable from `dart:ffi` alone, so this one platform
/// channel is the part of the bridge dart:ffi can't replace.
class NmtkWgpuRendererPlugin {
  NmtkWgpuRendererPlugin._();

  static const MethodChannel _channel = MethodChannel('nmtk_wgpu_renderer_plugin');

  /// Registers the `CVPixelBuffer` at native address [pixelBufferPtr] (as
  /// returned by `nmtk_renderer_get_pixel_buffer`) as a Flutter texture.
  /// Returns the texture id to pass to a `Texture` widget.
  static Future<int> registerTexture(int pixelBufferPtr) async {
    final id = await _channel.invokeMethod<int>('registerTexture', {
      'pixelBufferPtr': pixelBufferPtr,
    });
    if (id == null) {
      throw StateError('nmtk_wgpu_renderer_plugin: registerTexture returned null');
    }
    return id;
  }

  static Future<void> unregisterTexture(int textureId) {
    return _channel.invokeMethod<void>('unregisterTexture', {
      'textureId': textureId,
    });
  }

  /// Tells the engine a new frame is ready to be composited for [textureId].
  static Future<void> textureFrameAvailable(int textureId) {
    return _channel.invokeMethod<void>('textureFrameAvailable', {
      'textureId': textureId,
    });
  }
}
