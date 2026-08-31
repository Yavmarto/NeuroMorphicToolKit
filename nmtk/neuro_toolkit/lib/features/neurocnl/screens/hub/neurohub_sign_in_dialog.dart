import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/neurohub_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_client.dart';

Future<bool> showNeurohubSignInDialog(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const NeurohubSignInDialog(),
      ) ??
      false;
}

class NeurohubSignInDialog extends ConsumerStatefulWidget {
  const NeurohubSignInDialog({super.key});

  @override
  ConsumerState<NeurohubSignInDialog> createState() =>
      _NeurohubSignInDialogState();
}

class _NeurohubSignInDialogState extends ConsumerState<NeurohubSignInDialog> {
  NeurohubDeviceCodeStarted? _started;
  Timer? _countdown;
  int _secondsRemaining = 0;
  int _pollGeneration = 0;
  bool _starting = true;
  bool _polling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _pollGeneration++;
    _countdown?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _pollGeneration++;
    _countdown?.cancel();
    setState(() {
      _starting = true;
      _polling = false;
      _error = null;
      _started = null;
    });
    try {
      final client = ref.read(neurohubClientProvider);
      await client.oauthConfig();
      final started = await client.startDeviceAuthorization();
      if (!mounted) return;
      setState(() {
        _starting = false;
        _started = started;
        _secondsRemaining = started.expiresIn;
      });
      _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _secondsRemaining <= 0) {
          timer.cancel();
          return;
        }
        setState(() => _secondsRemaining--);
      });
      unawaited(_poll(started, started.interval));
    } on NeurohubException catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = _friendlyError(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error =
            'Neurohub sign-in could not start. Check your connection and try again.';
      });
    }
  }

  Future<void> _poll(
    NeurohubDeviceCodeStarted started,
    int intervalSeconds,
  ) async {
    final generation = ++_pollGeneration;
    setState(() {
      _polling = true;
      _error = null;
    });
    var interval = intervalSeconds;
    while (mounted && generation == _pollGeneration) {
      await Future<void>.delayed(Duration(seconds: interval));
      if (!mounted || generation != _pollGeneration) return;
      try {
        final result = await ref
            .read(neurohubClientProvider)
            .pollDeviceAuthorization(started.sessionId);
        if (!mounted || generation != _pollGeneration) return;
        interval = result.interval ?? interval;
        if (result.isSuccess && result.accessToken != null) {
          await ref
              .read(neurohubSessionProvider.notifier)
              .completeSignIn(result.accessToken!);
          ref.invalidate(neurohubWorkspacesProvider);
          if (mounted) Navigator.of(context).pop(true);
          return;
        }
        if (result.status == 'expired') {
          setState(() {
            _polling = false;
            _error = 'This code expired. Request a new code to continue.';
          });
          return;
        }
        if (result.status == 'denied') {
          setState(() {
            _polling = false;
            _error =
                'Sign-in was cancelled. Request a new code when you are ready.';
          });
          return;
        }
      } on NeurohubException catch (error) {
        setState(() {
          _polling = false;
          _error = _friendlyError(error);
        });
        return;
      } catch (_) {
        setState(() {
          _polling = false;
          _error = 'Neurohub could not check your sign-in. Try checking again.';
        });
        return;
      }
    }
  }

  String _friendlyError(NeurohubException error) {
    if (error.statusCode == 503) return error.message;
    return 'Neurohub sign-in is unavailable right now. Try again shortly.';
  }

  String get _remainingLabel {
    final minutes = _secondsRemaining ~/ 60;
    final seconds = _secondsRemaining % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')} remaining';
  }

  Future<void> _copyCode() async {
    final code = _started?.userCode;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(NmtkSnackBars.success(context, 'Sign-in code copied.'));
  }

  Future<void> _openLink() async {
    final url = _started?.verificationUri;
    if (url == null) return;
    final opened = await ref
        .read(neurohubExternalLinkLauncherProvider)
        .open(url);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        NmtkSnackBars.error(
          context,
          'The browser could not open. Copy the address and open it manually.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final started = _started;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: NmtkDesignTokens.dialogShape),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Sign in to Neurohub',
                style: Zeta.of(context).textStyles.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Connect your GitHub account to save and share Studio workspaces.',
              ),
              const SizedBox(height: 24),
              if (_starting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: CircularProgressIndicator(
                      // ZETA-MIGRATION-EXEMPT: determinate-only Zeta progress.
                    ),
                  ),
                )
              else if (started != null) ...<Widget>[
                // Allowed: single-topic surface — the GitHub device code.
                NmtkSurfaceCard(
                  title: 'Enter this code on GitHub',
                  subtitle: _remainingLabel,
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: SelectableText(
                          started.userCode,
                          key: const Key('neurohub-user-code'),
                          style: Zeta.of(context).textStyles.displaySmall,
                        ),
                      ),
                      const SizedBox(width: 16),
                      NmtkOutlinedButton(
                        label: 'Copy code',
                        icon: Icons.copy_outlined,
                        onPressed: _copyCode,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                NmtkOutlinedButton(
                  key: const Key('neurohub-open-sign-in-link'),
                  label: 'Open ${started.verificationUri}',
                  icon: Icons.open_in_new,
                  onPressed: _openLink,
                ),
                if (_polling) ...<Widget>[
                  const SizedBox(height: 16),
                  const Row(
                    children: <Widget>[
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          // ZETA-MIGRATION-EXEMPT: determinate-only Zeta progress.
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Waiting for you to finish in the browser…',
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              if (_error case final error?) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  error,
                  key: const Key('neurohub-sign-in-error'),
                  style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                    color: NmtkShellTokens.of(context).errorColor,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  NmtkOutlinedButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(width: 8),
                    NmtkPrimaryButton(
                      label: started == null ? 'Try again' : 'Check again',
                      onPressed: started == null
                          ? _start
                          : () => _poll(started, started.interval),
                    ),
                    if (started != null) ...<Widget>[
                      const SizedBox(width: 8),
                      NmtkPrimaryButton(label: 'New code', onPressed: _start),
                    ],
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
