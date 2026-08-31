import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/shell_tokens.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/workflow/pipeline_stepper.dart';

class NmtkWorkspaceShell extends StatelessWidget {
  const NmtkWorkspaceShell({
    super.key,
    required this.layoutId,
    required this.steps,
    required this.leftPane,
    required this.rightPane,
    this.splitBreakpoint = 1080,
  });

  final String layoutId;
  final List<NmtkPipelineStepData> steps;
  final Widget leftPane;
  final Widget rightPane;
  final double splitBreakpoint;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NmtkPipelineStepper(steps: steps),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useSplitLayout = constraints.maxWidth >= splitBreakpoint;
              if (useSplitLayout) {
                return Row(
                  key: Key('$layoutId-split-layout'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: SingleChildScrollView(
                        key: Key('$layoutId-left-pane'),
                        padding: EdgeInsets.symmetric(
                          horizontal: tokens.sectionGap,
                          vertical: tokens.sectionGap,
                        ),
                        child: leftPane,
                      ),
                    ),
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(
                        key: Key('$layoutId-right-pane'),
                        padding: EdgeInsets.symmetric(
                          horizontal: tokens.sectionGap,
                          vertical: tokens.sectionGap,
                        ),
                        child: rightPane,
                      ),
                    ),
                  ],
                );
              }

              return SingleChildScrollView(
                key: Key('$layoutId-stacked-layout'),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    KeyedSubtree(
                      key: Key('$layoutId-left-pane'),
                      child: leftPane,
                    ),
                    const SizedBox(height: 16),
                    KeyedSubtree(
                      key: Key('$layoutId-right-pane'),
                      child: rightPane,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
