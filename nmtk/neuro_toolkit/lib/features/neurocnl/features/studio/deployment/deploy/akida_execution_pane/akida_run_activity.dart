import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/studio_akida_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/presentation/studio_status_line.dart';

class AkidaRunActivity extends StatefulWidget {
  const AkidaRunActivity({super.key, required this.provider});

  final StudioAkidaDeployState provider;

  @override
  State<AkidaRunActivity> createState() => _AkidaRunActivityState();
}

class _AkidaRunActivityState extends State<AkidaRunActivity> {
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _elapsedLabel {
    final minutes = _elapsed.inMinutes;
    final seconds = _elapsed.inSeconds % 60;
    if (minutes == 0) return '${seconds}s';
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final operation = widget.provider.operationJob;
    final message =
        widget.provider.activityMessage ?? operation?.message ?? 'Running…';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioStatusLine(
          message: '$message  ·  $_elapsedLabel',
          tone: NmtkTone.neutral,
          loading: true,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          // Determinate only when the host reports progress; a benchmark poll
          // does, a single sample call does not.
          value: operation == null ? null : operation.progress / 100,
          minHeight: 4,
          borderRadius: BorderRadius.circular(
            NmtkShellTokens.of(context).radiusSm,
          ),
        ),
      ],
    );
  }
}
