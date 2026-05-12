import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';

enum _WorkflowChoice {
  researcher,
  hardware,
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _WorkflowChoice? _selectedWorkflow;

  Future<void> _complete() async {
    if (_selectedWorkflow == null) {
      return;
    }
    await ref.read(appStateProvider).completeOnboarding();
    if (!mounted) {
      return;
    }
    context.go('/workspace');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = Theme.of(context).extension<NmtkShellTokens>() ??
        NmtkShellTokens.fromColorScheme(
          theme.colorScheme,
          theme.brightness,
        );

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact =
                constraints.maxWidth < NmtkShellTokens.compactBreakpoint;
            final horizontalPadding = isCompact ? 24.0 : 32.0;

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.hub, size: 48),
                      const SizedBox(height: 32),
                      Text(
                        'Welcome to NMTK',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Choose the workspace NMTK opens first. You can switch workflows at any time.',
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: isCompact ? 32 : 48),
                      _WorkflowOptions(
                        isCompact: isCompact,
                        selectedWorkflow: _selectedWorkflow,
                        onChanged: (workflow) {
                          setState(() {
                            _selectedWorkflow = workflow;
                          });
                        },
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.center,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: isCompact ? double.infinity : 220,
                          ),
                          child: KeyedSubtree(
                            key: const Key('workflow-continue'),
                            child: NmtkPrimaryButton(
                              onPressed:
                                  _selectedWorkflow == null ? null : _complete,
                              icon: Icons.arrow_forward_rounded,
                              label: 'Enter workspace',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _selectedWorkflow == null
                            ? 'Select a workflow to continue.'
                            : 'This only sets your starting workspace.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.metadataForeground,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WorkflowOptions extends StatelessWidget {
  const _WorkflowOptions({
    required this.isCompact,
    required this.selectedWorkflow,
    required this.onChanged,
  });

  final bool isCompact;
  final _WorkflowChoice? selectedWorkflow;
  final ValueChanged<_WorkflowChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _WorkflowOptionCard(
        key: const Key('workflow-researcher'),
        title: 'Neural Researcher',
        description: 'Author SNNs, run simulations, and review analysis.',
        startsWith:
            'Starts with CNL Studio, simulation canvas, analysis tools.',
        icon: Icons.science,
        selected: selectedWorkflow == _WorkflowChoice.researcher,
        onSelected: () => onChanged(_WorkflowChoice.researcher),
      ),
      _WorkflowOptionCard(
        key: const Key('workflow-hardware'),
        title: 'Hardware Engineer',
        description: 'Compile, deploy, and validate edge targets.',
        startsWith:
            'Starts with NeuroChip, deployment checks, benchmark reports.',
        icon: Icons.memory,
        selected: selectedWorkflow == _WorkflowChoice.hardware,
        onSelected: () => onChanged(_WorkflowChoice.hardware),
      ),
    ];

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cards[0],
          const SizedBox(height: 16),
          cards[1],
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 16),
        Expanded(child: cards[1]),
      ],
    );
  }
}

class _WorkflowOptionCard extends StatelessWidget {
  const _WorkflowOptionCard({
    super.key,
    required this.title,
    required this.description,
    required this.startsWith,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final String description;
  final String startsWith;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = Theme.of(context).extension<NmtkShellTokens>() ??
        NmtkShellTokens.fromColorScheme(
          theme.colorScheme,
          theme.brightness,
        );
    final borderColor =
        selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant;
    final backgroundColor = selected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.20)
        : theme.colorScheme.surface;

    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $description $startsWith',
      onTap: onSelected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          onTap: onSelected,
          child: AnimatedContainer(
            duration: tokens.fastMotion,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              border: Border.all(color: borderColor, width: selected ? 2 : 1),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        icon,
                        size: 32,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    if (selected)
                      Icon(
                        Icons.check_circle_rounded,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  startsWith,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.metadataForeground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
