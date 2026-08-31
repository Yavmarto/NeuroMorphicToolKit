import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:neuro_toolkit/ui_core/visualization/renderer_interface.dart';

const double _rasterWindowMs = 1000.0;

class FragmentShaderNeuronRenderer implements NeuronRenderer {
  static const String _packageShaderPrefix =
      'packages/nmtk_ui_core/assets/shaders/';

  ui.FragmentProgram? _rasterProgram;
  ui.FragmentProgram? _particleProgram;
  ui.FragmentProgram? _densityProgram;
  ui.Image? _placeholder; // 1×1 blank, used until real textures arrive

  Size _size = Size.zero;

  final _ready = ValueNotifier<bool>(false);
  final _initError = ValueNotifier<String?>(null);
  final _frameNotifier = ValueNotifier<VisualizationFrame?>(null);
  // ponytail: separate notifiers so spike texture updates repaint independently
  // of frame updates — avoids blocking the UI while texture encodes.
  final _spikeTexture = ValueNotifier<ui.Image?>(null);
  final _densityTexture = ValueNotifier<ui.Image?>(null);
  final List<double> _rasterHistory = <double>[];

  bool _initializing = false;
  bool _textureBusy = false; // drop frames that arrive while encoding
  bool _disposed = false; // guards ValueNotifier writes racing with dispose()

  // ── Init ────────────────────────────────────────────────────────────────────

  Future<ui.FragmentProgram> _loadShader(String assetName) async {
    final candidates = <String>[
      '$_packageShaderPrefix$assetName',
      'assets/shaders/$assetName',
    ];

    Object? lastError;
    for (final candidate in candidates) {
      try {
        return ui.FragmentProgram.fromAsset(candidate);
      } catch (error) {
        lastError = error;
      }
    }

    throw StateError(
      'Failed to load shader $assetName. Tried ${candidates.join(', ')}. '
      'Last error: $lastError',
    );
  }

  static Future<ui.Image> _make1x1Image() async {
    final desc = ui.ImageDescriptor.raw(
      await ui.ImmutableBuffer.fromUint8List(Uint8List(4)), // R=G=B=A=0
      width: 1,
      height: 1,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await desc.instantiateCodec();
    return (await codec.getNextFrame()).image;
  }

  void _initShaders() async {
    if (_ready.value || _initializing) return;
    _initializing = true;
    _initError.value = null;
    try {
      _rasterProgram = await _loadShader('raster_plot.frag');
      _particleProgram = await _loadShader('spike_field.frag');
      _densityProgram = await _loadShader('density_map.frag');
      _placeholder = await _make1x1Image();
      if (_disposed) return;
      _spikeTexture.value = _placeholder;
      _densityTexture.value = _placeholder;
      _ready.value = true;
    } catch (e) {
      if (_disposed) return;
      _initError.value = '$e';
      debugPrint('FragmentShaderNeuronRenderer: shader load failed: $e');
    } finally {
      _initializing = false;
    }
  }

  // ── Texture encoding ────────────────────────────────────────────────────────

  /// Build a 1-row texture where each texel encodes one spike.
  ///
  /// Both raster_plot and spike_field shaders share this layout:
  ///   R = neuron_idx / totalNeuronCount   → raster row / particle x
  ///   G = time_ms / simulationTimeMs      → raster column / particle y
  ///   B = time_ms / simulationTimeMs      → spike_field birth_time_norm
  ///       (birthMs = B * uCurrentTimeMs = time_ms → correct fade age)
  ///   A = 255
  Uint8List _encodeSpikePixels(VisualizationFrame frame) {
    final isRaster = frame.scale == VisualizationScale.raster;
    final spikes = isRaster ? _rasterHistory : frame.spikeData;
    final count = spikes.length ~/ 2;
    final bytes = Uint8List(count * 4);
    final nScale = frame.totalNeuronCount > 0
        ? frame.totalNeuronCount.toDouble()
        : 1.0;
    final tScale = frame.simulationTimeMs > 0 ? frame.simulationTimeMs : 1000.0;

    for (int i = 0; i < count; i++) {
      final nNorm = (spikes[i * 2] / nScale).clamp(0.0, 1.0);
      final tNorm = isRaster
          ? (1.0 -
                    ((frame.simulationTimeMs - spikes[i * 2 + 1]) /
                        _rasterWindowMs))
                .clamp(0.0, 1.0)
          : (spikes[i * 2 + 1] / tScale).clamp(0.0, 1.0);
      final v = (tNorm * 255).round();
      bytes[i * 4 + 0] = (nNorm * 255).round(); // R: neuron → row/x
      bytes[i * 4 + 1] = v; // G: time → col/y
      bytes[i * 4 + 2] = v; // B: time norm → birth_time for fade
      bytes[i * 4 + 3] = 255; // A
    }
    return bytes;
  }

  static Uint8List _encodeDensityPixels(VisualizationFrame frame) {
    final grid = frame.densityGrid;
    final bytes = Uint8List(grid.length * 4);
    for (int i = 0; i < grid.length; i++) {
      final v = (grid[i].clamp(0.0, 1.0) * 255).round();
      bytes[i * 4 + 0] = v;
      bytes[i * 4 + 1] = v;
      bytes[i * 4 + 2] = v;
      bytes[i * 4 + 3] = 255;
    }
    return bytes;
  }

  static Future<ui.Image> _buildImage(
    Uint8List pixels,
    int width,
    int height,
  ) async {
    final buf = await ui.ImmutableBuffer.fromUint8List(pixels);
    final desc = ui.ImageDescriptor.raw(
      buf,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await desc.instantiateCodec();
    return (await codec.getNextFrame()).image;
  }

  int _spikeCountForFrame(VisualizationFrame frame) {
    if (frame.scale == VisualizationScale.raster) {
      return _rasterHistory.length ~/ 2;
    }
    return frame.spikeData.length ~/ 2;
  }

  void _updateRasterHistory(VisualizationFrame frame) {
    final windowStart = frame.simulationTimeMs - _rasterWindowMs;
    var removeCount = 0;
    while (removeCount + 1 < _rasterHistory.length &&
        _rasterHistory[removeCount + 1] < windowStart) {
      removeCount += 2;
    }
    if (removeCount > 0) {
      _rasterHistory.removeRange(0, removeCount);
    }
    _rasterHistory.addAll(frame.spikeData);
  }

  void _encodeTextures(VisualizationFrame frame) async {
    if (_textureBusy) return; // drop frame — previous encode still running
    _textureBusy = true;

    try {
      final spikeCount = _spikeCountForFrame(frame);

      // Spike texture (raster + particle modes)
      if (spikeCount > 0) {
        final pixels = _encodeSpikePixels(frame);
        final img = await _buildImage(pixels, spikeCount, 1);
        if (_disposed) {
          img.dispose();
          return;
        }
        final old = _spikeTexture.value;
        _spikeTexture.value = img;
        if (old != null && old != _placeholder) old.dispose();
      } else {
        final old = _spikeTexture.value;
        _spikeTexture.value = _placeholder;
        if (old != null && old != _placeholder) old.dispose();
      }

      // Density texture (density mode)
      final cellCount = frame.gridW * frame.gridH;
      if (cellCount > 0 && frame.densityGrid.isNotEmpty) {
        final pixels = _encodeDensityPixels(frame);
        final img = await _buildImage(pixels, cellCount, 1);
        if (_disposed) {
          img.dispose();
          return;
        }
        final old = _densityTexture.value;
        _densityTexture.value = img;
        if (old != null && old != _placeholder) old.dispose();
      }
    } catch (e) {
      debugPrint('FragmentShaderNeuronRenderer: texture encode failed: $e');
    } finally {
      _textureBusy = false;
    }
  }

  // ── NeuronRenderer interface ─────────────────────────────────────────────────

  @override
  void attach(Size size) {
    _size = size;
    _initShaders();
  }

  @override
  void pushFrame(VisualizationFrame frame) {
    if (frame.scale == VisualizationScale.raster) {
      _updateRasterHistory(frame);
    } else if (_rasterHistory.isNotEmpty) {
      _rasterHistory.clear();
    }
    _frameNotifier.value = frame;
    if (_ready.value) _encodeTextures(frame);
  }

  @override
  Widget buildSurface(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _ready,
      builder: (context, ready, _) {
        if (!ready) {
          return ValueListenableBuilder<String?>(
            valueListenable: _initError,
            builder: (context, initError, _) {
              if (initError == null) {
                return const Center(
                  child: Text('Loading visualization shaders...'),
                );
              }
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Visualization shaders failed to load.\n$initError',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          );
        }
        return ValueListenableBuilder<VisualizationFrame?>(
          valueListenable: _frameNotifier,
          builder: (context, frame, _) {
            if (frame == null) return const SizedBox.shrink();
            final spikeCount = _spikeCountForFrame(frame);
            return ValueListenableBuilder<ui.Image?>(
              valueListenable: _spikeTexture,
              builder: (context, spikeTex, _) {
                return ValueListenableBuilder<ui.Image?>(
                  valueListenable: _densityTexture,
                  builder: (context, densityTex, _) {
                    return CustomPaint(
                      size: _size,
                      painter: _ShaderPainter(
                        frame: frame,
                        rasterProgram: _rasterProgram!,
                        particleProgram: _particleProgram!,
                        densityProgram: _densityProgram!,
                        spikeTexture: spikeTex ?? _placeholder!,
                        densityTexture: densityTex ?? _placeholder!,
                        spikeCount: spikeCount.toDouble(),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _ready.dispose();
    _initError.dispose();
    _frameNotifier.dispose();
    final s = _spikeTexture.value;
    if (s != null && s != _placeholder) s.dispose();
    _spikeTexture.dispose();
    final d = _densityTexture.value;
    if (d != null && d != _placeholder) d.dispose();
    _densityTexture.dispose();
    _placeholder?.dispose();
  }
}

// ── Painter ─────────────────────────────────────────────────────────────────

class _ShaderPainter extends CustomPainter {
  final VisualizationFrame frame;
  final ui.FragmentProgram rasterProgram;
  final ui.FragmentProgram particleProgram;
  final ui.FragmentProgram densityProgram;
  final ui.Image spikeTexture;
  final ui.Image densityTexture;
  final double spikeCount;

  _ShaderPainter({
    required this.frame,
    required this.rasterProgram,
    required this.particleProgram,
    required this.densityProgram,
    required this.spikeTexture,
    required this.densityTexture,
    required this.spikeCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    ui.FragmentShader shader;

    if (frame.scale == VisualizationScale.density) {
      shader = densityProgram.fragmentShader();
      shader.setFloat(0, size.width);
      shader.setFloat(1, size.height);
      shader.setImageSampler(0, densityTexture); // uDensityGrid
      shader.setFloat(2, frame.gridW.toDouble()); // uGridDim.x
      shader.setFloat(3, frame.gridH.toDouble()); // uGridDim.y
    } else if (frame.scale == VisualizationScale.particle) {
      shader = particleProgram.fragmentShader();
      shader.setFloat(0, size.width);
      shader.setFloat(1, size.height);
      shader.setFloat(2, frame.simulationTimeMs); // uCurrentTimeMs
      shader.setFloat(3, 20.0); // uFadeDuration
      shader.setImageSampler(0, spikeTexture); // uSpikes
      shader.setFloat(4, spikeCount); // uSpikeCount
    } else {
      // raster
      shader = rasterProgram.fragmentShader();
      shader.setFloat(0, size.width);
      shader.setFloat(1, size.height);
      shader.setFloat(2, frame.totalNeuronCount.toDouble()); // uNeuronCount
      shader.setFloat(3, _rasterWindowMs); // uDuration
      shader.setFloat(4, _rasterWindowMs); // uTime
      shader.setImageSampler(0, spikeTexture); // uSpikes
      shader.setFloat(5, spikeCount); // uSpikeCount
    }

    paint.shader = shader;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _ShaderPainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.spikeTexture != spikeTexture ||
      oldDelegate.densityTexture != densityTexture;
}
