import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingStep> _steps = [
    OnboardingStep(
      title: 'Welcome to NMTK',
      description:
          'The NeuroMorphic ToolKit is your gateway to SNN engineering and simulation.',
      icon: Icons.hub,
    ),
    OnboardingStep(
      title: 'Modular Ecosystem',
      description:
          'Browse the Catalog to install specialized modules for simulation, hardware deployment, and more.',
      icon: Icons.extension,
    ),
    OnboardingStep(
      title: 'Python Powered',
      description:
          'NMTK uses isolated Python environments to run heavy-duty backends without dependency hell.',
      icon: Icons.terminal,
    ),
    OnboardingStep(
      title: 'Ready to Explore?',
      description:
          'Start by installing a module from the Catalog or check your Dashboard for status.',
      icon: Icons.rocket_launch,
    ),
  ];

  void _nextPage() {
    if (_currentPage < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _complete();
    }
  }

  void _complete() {
    ref.read(appStateProvider).completeOnboarding();
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandGradient =
        theme.extension<NmtkThemeExtension>()?.brandGradient ??
        const LinearGradient(
          colors: [Color(0xFFF6F6F8), Color(0xFFE9EEF8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: brandGradient),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (int page) {
                    setState(() {
                      _currentPage = page;
                    });
                  },
                  itemCount: _steps.length,
                  itemBuilder: (context, index) {
                    final step = _steps[index];
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: NmtkSurfaceCard(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                NmtkStatusBadge(
                                  label:
                                      'Step ${index + 1} of ${_steps.length}',
                                  tone: NmtkTone.info,
                                  icon: Icons.flag_outlined,
                                ),
                                const SizedBox(height: 24),
                                Icon(
                                  step.icon,
                                  size: 96,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(height: 32),
                                Text(
                                  step.title,
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  step.description,
                                  style: theme.textTheme.bodyLarge,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    NmtkOutlinedButton(onPressed: _complete, label: 'Skip'),
                    Row(
                      children: List.generate(
                        _steps.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentPage == index ? 20 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: _currentPage == index
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                    ),
                    NmtkPrimaryButton(
                      onPressed: _nextPage,
                      label: _currentPage == _steps.length - 1
                          ? 'Get Started'
                          : 'Next',
                      icon: _currentPage == _steps.length - 1
                          ? Icons.rocket_launch
                          : Icons.arrow_forward,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OnboardingStep {
  final String title;
  final String description;
  final IconData icon;

  OnboardingStep({
    required this.title,
    required this.description,
    required this.icon,
  });
}
