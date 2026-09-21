import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/system_resources.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/src/features/server_connection/presentation/system_resources_notifier.dart';

final _controlApiOverrideProvider = StateProvider<ControlApiService?>(
  (ref) => null,
);

const _sampleSnapshot = SystemResourcesSnapshot(
  cpuPercent: 42.5,
  cpuCores: 8,
  memoryTotal: 16_000_000_000,
  memoryUsed: 8_000_000_000,
  memoryPercent: 50,
  gpus: null,
  hostname: 'nmtk-host',
  platform: 'Linux-6.8-x86_64',
  uptimeSeconds: 100,
);

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('polls resources while the provider is watched', () async {
    var fetchCount = 0;
    final container = ProviderContainer(
      overrides: [
        selectedControlApiServiceProvider.overrideWith(
          (ref) => ref.watch(_controlApiOverrideProvider),
        ),
        systemResourcesFetcherProvider.overrideWithValue((_) async {
          fetchCount++;
          return _sampleSnapshot;
        }),
      ],
    );

    container.listen(systemResourcesProvider, (_, _) {});
    container.read(_controlApiOverrideProvider.notifier).state =
        ControlApiService(baseUri: Uri.parse('http://192.168.2.90:8090'));

    await _flushMicrotasks();
    expect(fetchCount, greaterThanOrEqualTo(1));
    expect(
      container.read(systemResourcesProvider).snapshot?.hostname,
      'nmtk-host',
    );

    await Future<void>.delayed(SystemResourcesNotifier.pollInterval);
    await _flushMicrotasks();
    expect(fetchCount, greaterThanOrEqualTo(2));

    container.dispose();
  });

  test('ignores stale responses after the selected host changes', () async {
    final pending = <String, Completer<SystemResourcesSnapshot?>>{};
    final container = ProviderContainer(
      overrides: [
        selectedControlApiServiceProvider.overrideWith(
          (ref) => ref.watch(_controlApiOverrideProvider),
        ),
        systemResourcesFetcherProvider.overrideWithValue((controlApi) {
          final host = controlApi.baseUri.host;
          pending.putIfAbsent(host, Completer.new);
          return pending[host]!.future;
        }),
      ],
    );

    container.listen(systemResourcesProvider, (_, _) {});
    container.read(_controlApiOverrideProvider.notifier).state =
        ControlApiService(baseUri: Uri.parse('http://192.168.2.90:8090'));
    await _flushMicrotasks();

    container.read(_controlApiOverrideProvider.notifier).state =
        ControlApiService(baseUri: Uri.parse('http://10.0.0.5:8090'));
    await _flushMicrotasks();

    pending['192.168.2.90']!.complete(
      const SystemResourcesSnapshot(
        cpuPercent: 1,
        cpuCores: 1,
        memoryTotal: 1,
        memoryUsed: 1,
        memoryPercent: 1,
        gpus: null,
        hostname: 'stale-host',
        platform: 'stale',
        uptimeSeconds: 1,
      ),
    );
    await _flushMicrotasks();

    pending['10.0.0.5']!.complete(_sampleSnapshot);
    await _flushMicrotasks();

    expect(
      container.read(systemResourcesProvider).snapshot?.hostname,
      'nmtk-host',
    );

    container.dispose();
  });
}
