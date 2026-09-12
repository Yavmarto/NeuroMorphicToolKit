import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/utils/force_directed_layout.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/network_2_5d_view.dart'
    show OrbitCamera;

/// Perspective projection for 3D brainviz node positions.
class BrainvizPerspective {
  const BrainvizPerspective({
    required this.size,
    required this.camera,
    required this.sceneScale,
  });

  final Size size;
  final OrbitCamera camera;
  final double sceneScale;
  static const double _focalLength = 520;

  Vec3 _rotate(Vec3 point) {
    if (camera.isIdentity) return point;
    final cosYaw = math.cos(camera.yaw);
    final sinYaw = math.sin(camera.yaw);
    final x1 = point.x * cosYaw + point.z * sinYaw;
    final z1 = -point.x * sinYaw + point.z * cosYaw;
    final cosPitch = math.cos(camera.pitch);
    final sinPitch = math.sin(camera.pitch);
    final y1 = point.y * cosPitch - z1 * sinPitch;
    final z2 = point.y * sinPitch + z1 * cosPitch;
    return Vec3(x1, y1, z2);
  }

  ({Offset screen, double depth, double scale}) project(Vec3 point) {
    final normalized = point * (220 / math.max(sceneScale, 1.0));
    final rotated = _rotate(normalized);
    final perspective = _focalLength / (_focalLength - rotated.z);
    final center = Offset(size.width / 2, size.height / 2);
    final projected = Offset(
      center.dx + rotated.x * perspective * camera.zoom,
      center.dy + rotated.y * perspective * camera.zoom,
    );
    return (
      screen: projected,
      depth: -rotated.z,
      scale: perspective * camera.zoom,
    );
  }
}
