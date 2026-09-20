import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/screens/server_access_gate.dart';
import 'package:neuro_toolkit/ui_core/widgets/empty_state.dart';
import 'package:neuro_toolkit/ui_core/widgets/surface_card.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

class _SlowReconnectNotifier extends ConnectNotifier {
  final _stall = Completer<void>();

  @override
  ConnectState build() => const ConnectState(savedHost: '192.168.2.90');

  @override
  Future<void> reconnectOnOpen() async {
    state = state.copyWith(phase: ConnectPhase.reconnecting);
    await _stall.future;
  }
}

void main() {
  testWidgets('reconnecting overlay uses calm surface card', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [connectNotifierProvider.overrideWith(_SlowReconnectNotifier.new)],
        child: const MaterialApp(
          home: ServerAccessGate(
            child: Scaffold(body: Center(child: Text('WORKSPACE'))),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('server-access-reconnecting')), findsOneWidget);
    expect(find.byType(NmtkSurfaceCard), findsOneWidget);
    expect(find.byType(ZetaProgressCircle), findsOneWidget);
    expect(find.text('Reconnecting to your server…'), findsOneWidget);
    expect(find.text('WORKSPACE'), findsNothing);
  });

  testWidgets('compact empty state uses muted title and small icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NmtkEmptyState(
            title: 'Workspace unavailable',
            message: 'Reconnect or choose a different server to continue.',
            icon: ZetaIcons.cloud_off,
            compact: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final icon = tester.widget<Icon>(find.byIcon(ZetaIcons.cloud_off));
    expect(icon.size, 24);
    expect(find.text('Workspace unavailable'), findsOneWidget);
  });
}
