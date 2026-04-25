import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/widgets/pipeline_stepper.dart';

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
                        padding: const EdgeInsets.fromLTRB(20, 20, 10, 20),
                        child: leftPane,
                      ),
                    ),
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(
                        key: Key('$layoutId-right-pane'),
                        padding: const EdgeInsets.fromLTRB(10, 20, 20, 20),
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
