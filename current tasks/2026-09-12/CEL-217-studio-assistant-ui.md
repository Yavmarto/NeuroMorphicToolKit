# CEL-217: Studio assistant chat + progressive build UI

**Status:** Done

## Delivered

- `features/neurocnl/features/studio/assistant/` — models, SSE service, Riverpod notifier, panel + timeline widgets
- `StudioAssistantHost` wired into `studio_screen.dart` (FAB → end drawer on desktop, bottom sheet on mobile)
- `studioAgentNotifier` parses SSE events from `POST /api/studio/agent/chat`
- `BuildTimeline`, `ToolCallCard`, `CnlPatchCard`; step chips call guarded `setActivePipelineStep` via `unlockedStepsProvider`

## Verification

```bash
cd nmtk/neuro_toolkit
flutter test test/features/neurocnl/features/studio/assistant/studio_assistant_widgets_test.dart
```

4 passed (Sep 2026).
