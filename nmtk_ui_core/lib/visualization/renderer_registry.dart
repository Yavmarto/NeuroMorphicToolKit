import 'package:nmtk_ui_core/visualization/fragment_shader_renderer.dart';
import 'package:nmtk_ui_core/visualization/renderer_interface.dart';

/// Creates the supported cross-platform neuron renderer.
NeuronRenderer createNeuronRenderer() => FragmentShaderNeuronRenderer();
