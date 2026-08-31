import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/target_reachability.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';

/// Reachability of a hardware target as probed by the backend container.
///
/// Carries the backend's `detail` string alongside the boolean so callers can
/// tell "SDK missing" from "SDK present, no card" without inventing a message.
final hardwareReachabilityProvider =
    FutureProvider.family<TargetReachability, String>((ref, targetId) async {
      final api = ref.read(apiClientProvider);
      return api.getTargetReachability(targetId);
    });

/// Readiness of the paired remote Akida host, or `null` when none is paired.
///
/// This is the correct source for Akida status in this app, and
/// [hardwareReachabilityProvider] is *not*: the backend's
/// `/targets/akida/reachability` probe does an in-container `import akida` plus a
/// local PCIe enumeration, so for the remote-host architecture Studio actually
/// uses it reports "not reachable" no matter how healthy the paired card is.
/// Launcher control's preflight talks to the host over SSH and to its control
/// service, and returns the state plus a human-readable reason.
///
/// Resolution order matches launcher control's own: its selected host id, then
/// a host flagged default, then the only host if there is exactly one.
final akidaHostReadinessProvider = FutureProvider<AkidaPairedHost?>((
  ref,
) async {
  final registry = ref.read(studioTargetRegistryServiceProvider);

  final selectedId = await registry.fetchSelectedAkidaHostId();
  if (selectedId != null) {
    return registry.fetchAkidaHostPreflight(selectedId);
  }

  final hosts = await registry.fetchAkidaHosts();
  if (hosts.isEmpty) return null;
  var resolved = hosts.first;
  for (final host in hosts) {
    if (host.isDefault) {
      resolved = host;
      break;
    }
  }
  return registry.fetchAkidaHostPreflight(resolved.id);
});

/// Readiness of the paired PYNQ-Z2 board, or `null` when none is paired.
///
/// Same reasoning as [akidaHostReadinessProvider], and for the same reason
/// [hardwareReachabilityProvider] is wrong here: the board is a separate
/// networked machine, so the backend container has neither the `pynq` package
/// nor a route to it and always answers "not reachable". Launcher control
/// reaches the board's own runtime and returns its overlay/DMA readiness plus a
/// human-readable reason, which is what `board.state` and
/// `board.lastPreflightMessage` carry.
///
/// Resolution order matches launcher control's own: its selected board id, then
/// a board flagged default, then the only board if there is exactly one.
final pynqBoardReadinessProvider = FutureProvider<PynqPairedBoard?>((
  ref,
) async {
  final registry = ref.read(studioTargetRegistryServiceProvider);

  final boards = await registry.fetchPynqBoards();
  if (boards.isEmpty) return null;

  final selectedId = await registry.fetchSelectedPynqBoardId();
  var resolved = boards.first;
  for (final board in boards) {
    if (board.id == selectedId) {
      resolved = board;
      break;
    }
    if (board.isDefault) {
      resolved = board;
    }
  }

  // Preflight talks to the board's runtime, so it fails outright until the
  // agent is installed — which is exactly when a freshly paired board most
  // needs to say so. Fall back to the stored record: it keeps the last known
  // `state` and `lastPreflightMessage`, so the UI can say "not provisioned
  // yet" instead of surfacing a bare transport error.
  try {
    return (await registry.fetchPynqBoardPreflight(resolved.id)).board;
  } catch (_) {
    return resolved;
  }
});
