import Cocoa
import CoreVideo
import FlutterMacOS

/// Wraps a `CVPixelBuffer` produced by the nmtk_wgpu Rust renderer as a
/// `FlutterTexture`. The renderer (Rust) owns the buffer's only +1 CF
/// reference for its whole lifetime — this wrapper must never `CFRelease`
/// it, only hand back an unretained reference each time the engine asks for
/// one. See `nmtk_wgpu`'s `SharedPixelBuffer` for the matching contract.
private final class NmtkPixelBufferTexture: NSObject, FlutterTexture {
  private let rawPixelBuffer: UnsafeRawPointer

  init(pixelBufferPtr: UInt) {
    self.rawPixelBuffer = UnsafeRawPointer(bitPattern: pixelBufferPtr)!
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    Unmanaged<CVPixelBuffer>.fromOpaque(rawPixelBuffer)
  }
}

public class NmtkWgpuRendererPlugin: NSObject, FlutterPlugin {
  private var registry: FlutterTextureRegistry?
  private var textures: [Int64: NmtkPixelBufferTexture] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "nmtk_wgpu_renderer_plugin", binaryMessenger: registrar.messenger)
    let instance = NmtkWgpuRendererPlugin()
    instance.registry = registrar.textures
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let registry = registry else {
      result(FlutterError(code: "no_registry", message: "Texture registry unavailable", details: nil))
      return
    }

    switch call.method {
    case "registerTexture":
      guard let args = call.arguments as? [String: Any],
            let ptrValue = args["pixelBufferPtr"] as? NSNumber else {
        result(FlutterError(code: "bad_args", message: "pixelBufferPtr missing", details: nil))
        return
      }
      let texture = NmtkPixelBufferTexture(pixelBufferPtr: ptrValue.uintValue)
      let textureId = registry.register(texture)
      textures[textureId] = texture
      result(textureId)

    case "unregisterTexture":
      guard let args = call.arguments as? [String: Any],
            let textureId = args["textureId"] as? NSNumber else {
        result(FlutterError(code: "bad_args", message: "textureId missing", details: nil))
        return
      }
      registry.unregisterTexture(textureId.int64Value)
      textures.removeValue(forKey: textureId.int64Value)
      result(nil)

    case "textureFrameAvailable":
      guard let args = call.arguments as? [String: Any],
            let textureId = args["textureId"] as? NSNumber else {
        result(FlutterError(code: "bad_args", message: "textureId missing", details: nil))
        return
      }
      registry.textureFrameAvailable(textureId.int64Value)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
