import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/nir_types_provider.dart';

NirParameterDef _param(NirNodeType type, String name) =>
    type.parameters.firstWhere((p) => p.name == name);

void main() {
  late ProviderContainer container;
  late Map<String, NirNodeType> registry;

  setUp(() {
    container = ProviderContainer();
    registry = container.read(nirNodeTypeMapProvider);
  });

  tearDown(() {
    container.dispose();
  });

  group('nir.LIF metadata parameters', () {
    late NirNodeType lif;

    setUp(() {
      lif = registry['nir.LIF']!;
    });

    test('exposes no per-node dt or beta control', () {
      // Both used to be offered here and neither was ever read: the backend
      // builds nir.LIF from tau/threshold/r/v_leak only, so editing them
      // changed nothing. The timestep belongs to the network (Network
      // Settings), and a per-node override is still reachable from CNL via
      // `annotated with metadata dt equal to <seconds>`.
      final Iterable<String> names = lif.parameters.map(
        (NirParameterDef p) => p.name,
      );
      expect(names, isNot(contains('dt')));
      expect(names, isNot(contains('beta')));
    });

    test('keeps tau in seconds, matching nir.LIF.tau', () {
      final NirParameterDef tau = _param(lif, 'tau');
      expect(tau.unit, 's');
      expect(tau.defaultValue, 0.02);
    });
  });

  group('nir.IF metadata parameters', () {
    test('exposes an editable beta parameter defaulting to 0.9', () {
      final NirNodeType ifType = registry['nir.IF']!;
      final NirParameterDef beta = _param(ifType, 'beta');
      expect(beta.type, 'float');
      expect(beta.defaultValue, 0.9);
    });
  });
}
