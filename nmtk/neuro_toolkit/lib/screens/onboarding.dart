import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:neuro_toolkit/providers/app_provider.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingStep> _steps = [
    OnboardingStep(
      title: 'Welcome to NMTK',
      description: 'The NeuroMorphic ToolKit is your gateway to SNN engineering and simulation.',
      icon: Icons.hub,
    ),
    OnboardingStep(
      title: 'Modular Ecosystem',
      description: 'Browse the Catalog to install specialized modules for simulation, hardware deployment, and more.',
      icon: Icons.extension,
    ),
    OnboardingStep(
      title: 'Python Powered',
      description: 'NMTK uses isolated Python environments to run heavy-duty backends without dependency hell.',
      icon: Icons.terminal,
    ),
    OnboardingStep(
      title: 'Ready to Explore?',
      description: 'Start by installing a module from the Catalog or check your Dashboard for status.',
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
    context.read<AppProvider>().completeOnboarding();
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
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
                  return Padding(
                    padding: const EdgeInsets.all(40.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          step.icon,
                          size: 100,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 40),
                        Text(
                          step.title,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          step.description,
                          style: theme.textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(40.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _complete,
                    child: const Text('Skip'),
                  ),
                  Row(
                    children: List.generate(
                      _steps.length,
                      (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentPage == index
                              ? theme.colorScheme.primary
                              : theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: _nextPage,
                    child: Text(_currentPage == _steps.length - 1
                        ? 'Get Started'
                        : 'Next'),
                  ),
                ],
              ),
            ),
          ],
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
