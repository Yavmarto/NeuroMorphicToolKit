import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

Widget buildHarness(Widget child, {ThemeData? theme}) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('NmtkSurfaceCard renders header and body content', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(
        const NmtkSurfaceCard(
          title: 'Launcher Section',
          subtitle: 'Shared subtitle',
          child: Text('Body content'),
        ),
      ),
    );

    expect(find.text('Launcher Section'), findsOneWidget);
    expect(find.text('Shared subtitle'), findsOneWidget);
    expect(find.text('Body content'), findsOneWidget);
    expect(find.byType(Container), findsAtLeastNWidgets(1));
  });

  testWidgets('NmtkEmptyState shows action button and handles tap', (
    WidgetTester tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      buildHarness(
        NmtkEmptyState(
          title: 'Nothing Here',
          message: 'Install a module to continue.',
          icon: Icons.widgets_outlined,
          action: NmtkPrimaryButton(
            label: 'Install',
            onPressed: () {
              tapped = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Nothing Here'), findsOneWidget);
    expect(find.text('Install a module to continue.'), findsOneWidget);
    expect(find.text('Install'), findsOneWidget);

    await tester.tap(find.text('Install'));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('NmtkStatusBadge applies label and icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(
        const NmtkStatusBadge(
          label: 'Running',
          tone: NmtkTone.success,
          icon: Icons.check_circle,
        ),
      ),
    );

    expect(find.text('Running'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('NmtkWorkspaceOverviewCard renders chips and trailing content', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(
        const NmtkWorkspaceOverviewCard(
          title: 'Deployment Workspace',
          subtitle: 'Shared operational shell',
          message: 'Use this surface to prepare and track the flow.',
          trailing: Icon(Icons.rocket_launch),
          chips: [
            NmtkInfoChip(
              icon: Icons.memory_outlined,
              label: 'Target',
              value: 'PYNQ-Z2',
            ),
            NmtkInfoChip(
              icon: Icons.flash_on_outlined,
              label: 'Mode',
              value: 'Ready',
            ),
          ],
        ),
      ),
    );

    expect(find.text('Deployment Workspace'), findsOneWidget);
    expect(find.text('Shared operational shell'), findsOneWidget);
    expect(
      find.text('Use this surface to prepare and track the flow.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.rocket_launch), findsOneWidget);
    expect(find.text('Target: PYNQ-Z2'), findsOneWidget);
    expect(find.text('Mode: Ready'), findsOneWidget);
  });

  testWidgets(
    'NmtkWorkspaceOverviewCard omits chip wrap when chips are empty',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        buildHarness(
          const NmtkWorkspaceOverviewCard(
            title: 'Deployment Workspace',
            subtitle: 'Shared operational shell',
            message: 'No metadata chips are currently available.',
          ),
        ),
      );

      expect(
        find.text('No metadata chips are currently available.'),
        findsOneWidget,
      );
      expect(find.byType(NmtkInfoChip), findsNothing);
      expect(find.byType(Wrap), findsNothing);
    },
  );

  testWidgets('NmtkInfoChip renders icon and combined label text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(
        const NmtkInfoChip(
          icon: Icons.storage_outlined,
          label: 'Artifact',
          value: 'firmware.bin',
        ),
      ),
    );

    expect(find.text('Artifact: firmware.bin'), findsOneWidget);
    expect(find.byIcon(Icons.storage_outlined), findsOneWidget);
  });

  testWidgets('NmtkWorkflowStepRow renders icon title and subtitle', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(
        const NmtkWorkflowStepRow(
          title: 'Export artifact',
          subtitle: 'Overlay artifact can be generated for the current spec.',
          tone: NmtkTone.success,
          icon: Icons.check_circle,
        ),
      ),
    );

    expect(find.text('Export artifact'), findsOneWidget);
    expect(
      find.text('Overlay artifact can be generated for the current spec.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('NmtkKeyValueRow renders label and primary value text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(
        const NmtkKeyValueRow(label: 'Synapses', value: '4096'),
        theme: AppTheme.lightTheme,
      ),
    );

    final valueText = tester.widget<Text>(find.text('4096'));

    expect(find.text('Synapses'), findsOneWidget);
    expect(find.text('4096'), findsOneWidget);
    expect(valueText.style?.color, AppTheme.lightTheme.colorScheme.primary);
  });

  testWidgets('NmtkSectionCard keeps neutral header content and actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(
        const NmtkSectionCard(
          title: 'Section Title',
          subtitle: 'Section Subtitle',
          leading: Icon(Icons.dashboard_outlined),
          trailing: Icon(Icons.more_horiz),
          child: Text('Section body'),
        ),
        theme: AppTheme.lightTheme,
      ),
    );

    final containerFinder = find.byWidgetPredicate(
      (widget) => widget is Container && widget.decoration is BoxDecoration,
    ).first;
    final container = tester.widget<Container>(containerFinder);
    final decoration = container.decoration as BoxDecoration;

    expect(find.byType(NmtkSurfaceCard), findsOneWidget);
    expect(find.text('Section Title'), findsOneWidget);
    expect(find.text('Section Subtitle'), findsOneWidget);
    expect(find.text('Section body'), findsOneWidget);
    expect(find.byIcon(Icons.dashboard_outlined), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    expect(decoration.color, const Color(0xFFF1F8FF));
  });

  testWidgets('NmtkSectionCard applies non-neutral tone through surface card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(
        const NmtkSectionCard(
          title: 'Attention',
          tone: NmtkTone.warning,
          child: Text('Check the generated warnings.'),
        ),
        theme: AppTheme.lightTheme,
      ),
    );

    final containerFinder = find.byWidgetPredicate(
      (widget) => widget is Container && widget.decoration is BoxDecoration,
    ).first;
    final container = tester.widget<Container>(containerFinder);
    final decoration = container.decoration as BoxDecoration;

    expect(decoration.color, const Color(0xFFFEF2E2));
    expect(find.text('Check the generated warnings.'), findsOneWidget);
  });

  testWidgets('NmtkResultCard wraps section semantics for result content', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(
        const NmtkResultCard(
          title: 'Deployment Complete',
          subtitle: 'Artifacts are ready for handoff.',
          tone: NmtkTone.success,
          leading: Icon(Icons.check_circle_outline),
          child: Text('All outputs were generated successfully.'),
        ),
        theme: AppTheme.lightTheme,
      ),
    );

    expect(find.byType(NmtkSectionCard), findsOneWidget);
    expect(find.text('Deployment Complete'), findsOneWidget);
    expect(find.text('Artifacts are ready for handoff.'), findsOneWidget);
    expect(
      find.text('All outputs were generated successfully.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets(
    'NmtkProgressCard uses determinate progress and trailing details',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        buildHarness(
          const NmtkProgressCard(
            title: 'Deployment Progress',
            subtitle: 'Streaming artifact state',
            progress: 0.65,
            statusIcon: Icons.sync,
            statusColor: Colors.blue,
            statusLabel: 'Uploading bitstream',
            trailing: Icon(Icons.schedule),
            details: [Text('65% complete')],
          ),
        ),
      );

      final progressIndicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );

      expect(progressIndicator.value, 0.65);
      expect(find.text('Uploading bitstream'), findsOneWidget);
      expect(find.text('65% complete'), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
    },
  );

  testWidgets('NmtkProgressCard supports indeterminate error rendering', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(
        const NmtkProgressCard(
          title: 'Deployment Progress',
          subtitle: 'Streaming artifact state',
          statusIcon: Icons.error_outline,
          statusColor: Colors.red,
          statusLabel: 'Upload failed',
          errorText: 'Serial transport disconnected.',
          details: [Text('Reconnect the device and retry.')],
        ),
      ),
    );

    final progressIndicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    final statusText = tester.widget<Text>(find.text('Upload failed'));

    expect(progressIndicator.value, isNull);
    expect(progressIndicator.color, isNotNull);
    expect(statusText.style?.color, isNotNull);
    expect(find.text('Serial transport disconnected.'), findsOneWidget);
    expect(find.text('Reconnect the device and retry.'), findsOneWidget);
  });

  testWidgets('NmtkErrorCard renders plain text without selectable mode', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(
        const NmtkErrorCard(
          message: 'The deploy command returned exit code 1.',
        ),
      ),
    );

    expect(find.text('Workflow Error'), findsOneWidget);
    expect(
      find.text('The deploy command returned exit code 1.'),
      findsOneWidget,
    );
    expect(find.byType(SelectableText), findsNothing);
  });

  testWidgets('NmtkErrorCard renders selectable text with prefix and action', (
    WidgetTester tester,
  ) async {
    var retried = false;

    await tester.pumpWidget(
      buildHarness(
        NmtkErrorCard(
          message: 'The runtime log is available for inspection.',
          selectable: true,
          prefix: const Text('Captured stderr'),
          action: TextButton(
            onPressed: () {
              retried = true;
            },
            child: const Text('Retry'),
          ),
        ),
      ),
    );

    expect(find.text('Captured stderr'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(retried, isTrue);
  });

  testWidgets('NmtkSummaryCard renders title description and chips', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(
        const NmtkSummaryCard(
          title: 'Target Summary',
          description: 'Compiled artifacts are ready for deployment.',
          chips: [
            NmtkInfoChip(
              icon: Icons.memory_outlined,
              label: 'Target',
              value: 'Teensy 4.1',
            ),
            NmtkInfoChip(
              icon: Icons.folder_zip_outlined,
              label: 'Bundle',
              value: 'ready',
            ),
          ],
        ),
      ),
    );

    expect(find.text('Target Summary'), findsOneWidget);
    expect(
      find.text('Compiled artifacts are ready for deployment.'),
      findsOneWidget,
    );
    expect(find.text('Target: Teensy 4.1'), findsOneWidget);
    expect(find.text('Bundle: ready'), findsOneWidget);
  });
}
