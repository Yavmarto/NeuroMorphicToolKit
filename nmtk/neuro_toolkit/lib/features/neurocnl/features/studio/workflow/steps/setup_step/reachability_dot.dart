import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/target_availability_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/setup_step/support.dart';

class ReachabilityDot extends ConsumerWidget {
  const ReachabilityDot({super.key, required this.targetId});

  final String targetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = NmtkShellTokens.of(context);
    final subtle = Zeta.of(context).colors.mainSubtle;

    final launcherProbed = usesLauncherReadinessProbe(targetId);
    final ({Color color, String message}) status = switch (targetId) {
      'akida' => _akidaStatus(ref, tokens, subtle),
      'pynq' => _pynqStatus(ref, tokens, subtle),
      _ => _backendProbeStatus(ref, tokens, subtle),
    };

    // Readiness is otherwise only refreshed by Check Readiness, which lives
    // inside the deploy workspace — several steps away from where the device is
    // paired. Tapping the dot re-runs it where the user actually is.
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: status.color, shape: BoxShape.circle),
    );
    final message = launcherProbed
        ? '${status.message}\nTap to re-check.'
        : status.message;

    return Tooltip(
      message: message,
      child: launcherProbed
          ? InkWell(
              onTap: () => targetId == 'akida'
                  ? _recheckAkida(context, ref)
                  : _recheckPynq(context, ref),
              customBorder: const CircleBorder(),
              // The dot is 8px; pad the hit target out to something tappable
              // without moving the dot itself.
              child: Padding(padding: const EdgeInsets.all(6), child: dot),
            )
          : dot,
    );
  }

  /// Re-runs the readiness check and reports what came back.
  ///
  /// Invalidating alone looked broken: the round trip is real, but the whole
  /// result is two pixels of colour, and a re-derived state is identical
  /// whenever the underlying fault has not changed — which is the normal case
  /// for a host that needs a power cycle or a repair. With no spinner and no
  /// message, tapping appeared to do nothing at all. The snackbar mirrors
  /// `studio_step_drawer.dart`'s recheck.
  Future<void> _recheckAkida(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    ref.invalidate(akidaHostReadinessProvider);
    try {
      final host = await ref.read(akidaHostReadinessProvider.future);
      if (!context.mounted) return;
      if (host == null) {
        messenger.showSnackBar(
          NmtkSnackBars.error(
            context,
            'No Akida host is paired — add one under Manage Targets.',
          ),
        );
        return;
      }
      final detail = host.lastReadinessMessage.trim();
      final text = detail.isEmpty
          ? host.state.label
          : '${host.state.label} — $detail';
      // Only `ready` is a success: the user tapped to find out whether the
      // re-check cleared the problem, and for every other state it did not.
      // The amber-vs-red nuance stays where it persists, on the dot itself.
      messenger.showSnackBar(
        host.state == AkidaPairedHostState.ready
            ? NmtkSnackBars.success(context, text)
            : NmtkSnackBars.error(context, text),
      );
    } catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        NmtkSnackBars.error(
          context,
          'Could not re-check the Akida host: $error',
        ),
      );
    }
  }

  /// PYNQ: readiness of the paired board, reported by launcher control.
  ///
  /// Counterpart to [_recheckAkida]; see [pynqBoardReadinessProvider] for why
  /// the backend probe cannot answer this.
  ///
  /// Does one thing the Akida version does not: for a board nothing has
  /// contacted yet it runs the SSH connectivity test first. Readiness alone
  /// cannot move that board — preflight needs the board agent, which is not
  /// installed yet — so a re-check used to return the stored state unchanged
  /// however many times it was tapped. Testing first means the dot can advance
  /// from where the board was paired, instead of sending the user to a different
  /// step to press a different button.
  Future<void> _recheckPynq(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final current = await ref.read(pynqBoardReadinessProvider.future);
      if (current != null && current.state == PynqBoardState.unpaired) {
        await ref
            .read(studioTargetRegistryServiceProvider)
            .testPynqBoardConnection(current.id);
      }
    } catch (_) {
      // A failed SSH test is not the verdict — it is one input to it. Fall
      // through to the readiness read, which reports the resulting state (and
      // its reason) rather than a bare transport error.
    }

    ref.invalidate(pynqBoardReadinessProvider);
    try {
      final board = await ref.read(pynqBoardReadinessProvider.future);
      if (!context.mounted) return;
      if (board == null) {
        messenger.showSnackBar(
          NmtkSnackBars.error(
            context,
            'No PYNQ board is paired — add one under Manage Targets.',
          ),
        );
        return;
      }
      final detail = board.lastPreflightMessage.trim();
      final nextStep = _pynqNextStep(board.state);
      final text = <String>[
        board.state.label,
        if (detail.isNotEmpty) detail,
        ?nextStep,
      ].join(' — ');
      messenger.showSnackBar(
        board.state == PynqBoardState.ready
            ? NmtkSnackBars.success(context, text)
            : NmtkSnackBars.error(context, text),
      );
    } catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        NmtkSnackBars.error(
          context,
          'Could not re-check the PYNQ board: $error',
        ),
      );
    }
  }

  /// The in-app action that clears this board state, or null when there is none.
  ///
  /// A state label on its own says what is wrong and not what to do about it,
  /// and every one of these is one button press away in the PYNQ workspace. All
  /// of them name a control in the app; none sends the user to a terminal.
  String? _pynqNextStep(PynqBoardState state) {
    return switch (state) {
      PynqBoardState.unpaired ||
      PynqBoardState.reachable ||
      PynqBoardState.provisionFailed =>
        'Choose Install board runtime in Deploy → PYNQ-Z2.',
      PynqBoardState.runtimeInstalled || PynqBoardState.overlayMissing =>
        'Choose Install overlay in Deploy → PYNQ-Z2.',
      PynqBoardState.degradedOptionalCapability ||
      PynqBoardState.preflightFailed =>
        'Choose Restart runtime in Deploy → PYNQ-Z2, then Check readiness.',
      PynqBoardState.error =>
        'Check the board is powered and on the network, then re-check.',
      PynqBoardState.provisioning || PynqBoardState.ready => null,
    };
  }

  ({Color color, String message}) _pynqStatus(
    WidgetRef ref,
    NmtkShellTokens tokens,
    Color subtle,
  ) {
    return ref
        .watch(pynqBoardReadinessProvider)
        .when(
          skipLoadingOnRefresh: false,
          data: (board) {
            if (board == null) {
              return (
                color: subtle,
                message: 'No PYNQ board paired — add one under Manage Targets.',
              );
            }
            final reason = board.lastPreflightMessage.trim();
            final detail = reason.isEmpty ? board.state.label : reason;
            return (
              color: _colorForBoardState(board.state, tokens, subtle),
              message: '${board.displayName} · ${board.state.label}\n$detail',
            );
          },
          loading: () => (color: subtle, message: 'Checking PYNQ board…'),
          error: (error, _) => (
            color: tokens.errorColor,
            message:
                'Cannot reach launcher control to check the PYNQ board: $error',
          ),
        );
  }

  /// Maps the ten board states onto the suite's three status colours.
  ///
  /// `overlayMissing` is amber, not red: the board is paired, provisioned and
  /// answering — it just has no bitstream yet, which Install Overlay fixes in
  /// one click. Red is reserved for states the user cannot clear from the
  /// workspace.
  Color _colorForBoardState(
    PynqBoardState state,
    NmtkShellTokens tokens,
    Color subtle,
  ) {
    return switch (state) {
      PynqBoardState.ready => tokens.healthyColor,
      PynqBoardState.overlayMissing ||
      PynqBoardState.degradedOptionalCapability ||
      PynqBoardState.runtimeInstalled => tokens.degradedColor,
      PynqBoardState.provisionFailed ||
      PynqBoardState.preflightFailed ||
      PynqBoardState.error => tokens.errorColor,
      PynqBoardState.provisioning => tokens.runningColor,
      PynqBoardState.unpaired || PynqBoardState.reachable => subtle,
    };
  }

  /// Akida: readiness of the paired remote host, reported by launcher control.
  ({Color color, String message}) _akidaStatus(
    WidgetRef ref,
    NmtkShellTokens tokens,
    Color subtle,
  ) {
    return ref
        .watch(akidaHostReadinessProvider)
        .when(
          // Without this the dot keeps rendering the previous value for the
          // whole round trip, so a re-check that changes nothing produces no
          // visible frame at all.
          skipLoadingOnRefresh: false,
          data: (host) {
            if (host == null) {
              return (
                color: subtle,
                message: 'No Akida host paired — add one under Manage Targets.',
              );
            }
            final reason = host.lastReadinessMessage.trim();
            final detail = reason.isEmpty ? host.state.label : reason;
            return (
              color: _colorForHostState(host.state, tokens, subtle),
              message: '${host.displayName} · ${host.state.label}\n$detail',
            );
          },
          loading: () => (color: subtle, message: 'Checking Akida host…'),
          error: (error, _) => (
            color: tokens.errorColor,
            message:
                'Cannot reach launcher control to check the Akida host: $error',
          ),
        );
  }

  /// Every other target: probed by the backend container itself.
  ({Color color, String message}) _backendProbeStatus(
    WidgetRef ref,
    NmtkShellTokens tokens,
    Color subtle,
  ) {
    final sdkAvailable =
        ref.watch(targetAvailabilityProvider).value?[targetId] ?? true;
    return ref
        .watch(hardwareReachabilityProvider(targetId))
        .when(
          // `detail` is the backend's own words ("3 device(s) found", "akida SDK not
          // installed"); the SDK-availability fallback only covers an empty detail.
          data: (result) => (
            color: result.reachable
                ? tokens.healthyColor
                : (sdkAvailable ? tokens.degradedColor : tokens.errorColor),
            message: result.detail.isNotEmpty
                ? result.detail
                : result.reachable
                ? 'Reachable'
                : (sdkAvailable
                      ? 'SDK installed — hardware not connected'
                      : 'SDK not installed'),
          ),
          loading: () => (color: subtle, message: 'Checking…'),
          error: (error, _) =>
              (color: tokens.errorColor, message: 'Unreachable: $error'),
        );
  }

  /// Maps the 15 paired-host states onto the suite's three status colours.
  ///
  /// Simulator-only and the degraded states are amber rather than red: the host
  /// works, it just cannot earn hardware verification. Showing them red is what
  /// made a partially-working host indistinguishable from a broken one.
  Color _colorForHostState(
    AkidaPairedHostState state,
    NmtkShellTokens tokens,
    Color subtle,
  ) {
    return switch (state) {
      AkidaPairedHostState.ready => tokens.healthyColor,
      AkidaPairedHostState.degraded ||
      AkidaPairedHostState.degradedOptionalCapability ||
      AkidaPairedHostState.simulatorOnly => tokens.degradedColor,
      AkidaPairedHostState.blocked ||
      AkidaPairedHostState.preflightFailed ||
      AkidaPairedHostState.provisionFailed ||
      AkidaPairedHostState.error => tokens.errorColor,
      AkidaPairedHostState.bootstrapping ||
      AkidaPairedHostState.installingRuntime ||
      AkidaPairedHostState.verifyingSdk => tokens.runningColor,
      AkidaPairedHostState.unknown ||
      AkidaPairedHostState.unpaired ||
      AkidaPairedHostState.reachable ||
      AkidaPairedHostState.pending => subtle,
    };
  }
}
