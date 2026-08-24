import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/visualization/fragment_shader_renderer.dart';
import 'package:nmtk_ui_core/visualization/renderer_registry.dart';

void main() {
  test('creates the supported fragment-shader renderer', () {
    final renderer = createNeuronRenderer();

    expect(renderer, isA<FragmentShaderNeuronRenderer>());

    renderer.dispose();
  });
}
