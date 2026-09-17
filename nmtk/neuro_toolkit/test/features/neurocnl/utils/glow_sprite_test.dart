import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/utils/glow_sprite.dart';

void main() {
  test('radial glow sprite uses additive blending', () {
    final paint = GlowSprite.radial(
      center: const Offset(10, 10),
      radius: 20,
      color: Colors.purple,
      intensity: 0.5,
    );

    expect(paint.blendMode, BlendMode.plus);
    expect(paint.shader, isA<ui.Gradient>());
  });

  test('ring draws without error on a recorder canvas', () {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    GlowSprite.ring(
      canvas,
      radiusX: 40,
      radiusY: 24,
      color: Colors.purple,
      alpha: 0.2,
    );

    final picture = recorder.endRecording();
    expect(picture, isNotNull);
    picture.dispose();
  });
}
