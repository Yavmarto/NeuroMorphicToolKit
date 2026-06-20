# Training Animation & Visualization — Codebase Analysis

> **Scope.** End-to-end audit of how the NeuroMorphicToolKit (NMTK) monorepo animates
> and visualises model **training** (live loss, epoch progress, post-run spiking
> playback). Each claim below is anchored to a `file_path:line_number` so it can be
> verified from the editor.
>
> **TL;DR.** All in-app training visualization lives in the **`neurocnl`** module.
> One live SSE event stream (`progress_bus` → FastAPI SSE → Dart SSE parser →
> Riverpod provider) drives three synchronized animations: a `CustomPainter` loss
> curve with a trailing cursor, a scale-pulse heartbeat on the "Train" pipeline
> chip, and a one-shot checkmark stroke on success. A separate, much larger
> `AnimatedSnnPlayback` widget re-animates completed SNN simulations (cursor,
> zoom, glow trails). Other modules (Neurobench, Neurohub, Neurochip, Neurosim,
> Neurosense) have **no training visualization of their own**. Neuro-Dream-Hand
> exposes a static `plot_loss` matplotlib helper for CLI scripts only.

---

## 1. Module-by-module index

| Module | Has live training UI? | File(s) | Notes |
|---|---|---|---|
| `neurocnl` | **Yes — full** | `frontend/lib/widgets/training_inspector_panel.dart`, `frontend/lib/widgets/canvas/loss_curve_chart.dart`, `frontend/lib/widgets/canvas/animated_snn_playback.dart`, `backend/app/routers/training.py`, `backend/app/services/progress_bus.py`, `backend/app/services/training_service.py`, `neurocnl/training/{snntorch,sleep_pes}_adapter.py` | The single source of truth |
| `nmtk_ui_core` | Reusable stepper pulse primitive | `lib/widgets/pipeline_stepper.dart`, `lib/widgets/snn_workflow_stepper.dart` | Generic, no domain knowledge |
| `Neuro-Dream-Hand` | CLI-only matplotlib export | `neurodreamhand/learning/sleep_pes.py:282` (`plot_loss`) | Saved to PNG, never streamed |
| `neurocnl` (server-side fallback) | Matplotlib offline | `neurocnl/visualization.py` | Spike raster, voltage traces, topology, weight evolution; returned as base64 PNG via `to_html`; **not currently wired to live training** |
| `Neurobench` | None | — | |
| `Neurohub` | None | — | |
| `Neurochip` | None | — | |
| `Neurosim` | None | — | |
| `Neurosense` | None | — | |

---

## 2. Live training loss UX (`neurocnl`)

### 2.1 State machine

`frontend/lib/widgets/training_inspector_panel.dart:14` declares a 6-state machine on `TrainingProviderStatus` (defined in `providers/training_provider.dart:14`):

```
idle → loadingCapabilities → submitting → polling → success
                                                  ↘ failure
```

The panel `build` is a Dart 3 `switch` expression over this enum
(`training_inspector_panel.dart:236`) that swaps in one of five sub-widgets —
`_Loading`, `_Submitting`, `_Idle`, `_Polling`, `_Success`, `_Failure`. This
mirrors the simulator panel's decomposition style (per the source comment at
`training_inspector_panel.dart:255`).

### 2.2 Auto-start pipeline

The training workflow is **event-driven, not user-driven**. A `Provider`
selector named `trainingPanelPrereqProvider` (`training_inspector_panel.dart:25`)
combines parse status, validation status, spec text, and dataset selection into
a single record. When **all** prereqs turn green, a `postFrameCallback` in the
panel calls `_autoStart(cap)` (`training_inspector_panel.dart:158`) which
`POST /api/training/run`s and transitions to `polling`.

`features` referenced in the prereq check (`training_inspector_panel.dart:216`):

- spec is non-empty,
- `parseStatus == success` and `parseErrors == 0`,
- `validateStatus == success` and `validateOverall == true`,
- `selectedDataset != null` and `selectedDatasetPath != null`,
- at least one available backend in `state.capabilities`.

Blockers are surfaced as a bulleted list (`training_inspector_panel.dart:329`)
so the user sees the exact missing prereq, not a generic "preparing…" card.

### 2.3 Wall-clock elapsed timer

A `Timer.periodic(seconds: 1)` in the panel state (`training_inspector_panel.dart:128`)
shows the user a `mm:ss` (or `h:mm:ss`) clock formatted by `_fmtDuration` at
`training_inspector_panel.dart:140`. It starts on submit and stops on success
(`_stopTimer` in `_triggerCheck`, `training_inspector_panel.dart:146`).

### 2.4 Animated checkmark on success

`training_inspector_panel.dart:94` holds an `AnimationController` (`_checkCtrl`)
with a 600 ms `Curves.easeOutCubic` curve. `_CheckPainter` at
`training_inspector_panel.dart:755` draws two phases:

- `0..0.4` — circle arc stroke (alpha-fades in as `progress / 0.4`),
- `0.4..1.0` — two-segment checkmark path (`A → B` then `B → C`), with the
  second segment only drawn once the first is complete.

`_triggerCheck` (`training_inspector_panel.dart:146`) is a one-shot
idempotent gate (guarded by `_checkPlayed`) that respects
`MediaQuery.disableAnimationsOf(context)` by snapping to `value = 1.0` instead
of animating.

### 2.5 Live loss curve

`frontend/lib/widgets/canvas/loss_curve_chart.dart` is a `StatelessWidget` that
delegates all drawing to a private `_LossCurvePainter extends CustomPainter`
(`loss_curve_chart.dart:100`). Visual language matches the simulator's
`TimeSeriesChart`:

- Filled area at 8 % opacity under the curve (`loss_curve_chart.dart:204`),
- 1.8 px rounded line on top (`loss_curve_chart.dart:207`),
- 4 horizontal grid lines + 5 epoch ticks + `"Epoch"` axis label
  (`loss_curve_chart.dart:150-193`),
- **Trailing cursor**: while `losses.length < totalEpochs`, a vertical line +
  3.5 px filled dot is drawn at the last received point
  (`loss_curve_chart.dart:225-235`); on completion the dot stays but loses the
  vertical line (`loss_curve_chart.dart:236-243`).

The chart is used twice in the panel — once during polling
(`training_inspector_panel.dart:488`) and once in success state
(`training_inspector_panel.dart:605`), with success falling back to
`result.lossCurve` if the live epoch list is empty.

### 2.6 Pipeline chip heartbeat

The shared stepper at `nmtk_ui_core/lib/widgets/pipeline_stepper.dart:17-23`
documents the intent explicitly:

> "Monotonically increasing counter — increment this to trigger a brief
> scale-pulse on the step chip while it is in `NmtkStepStatus.running`. …
> Intended use: wire to a training `epochTick` counter so the chip visually
> heartbeats each time a training epoch completes."

Wired up in two places:

- `frontend/lib/widgets/pipeline_bar.dart:52` — `pulseTick: trainingState.epochTick`
  in the inline `_Polling` step card.
- `frontend/lib/screens/studio/studio_top_bar.dart:63` — `epochPulseTick: trainingState.epochTick`
  on the top-bar stepper.

`NmtkPipelineStepper._PipelineStep.didUpdateWidget`
(`pipeline_stepper.dart:285`) advances the `_pulseCtrl` `AnimationController`
on every increment, gated on `status == running` and
`MediaQuery.disableAnimationsOf(context)`. The chip is then wrapped in
`Transform.scale(scale: _pulseScale.value)` (`pipeline_stepper.dart:340`).

---

## 3. End-to-end event flow

```
snntorch_adapter.run() / sleep_pes_adapter.run()      (worker thread)
        │  progress({type:'epoch', epoch:N, total_epochs, loss, elapsed_seconds})
        ▼
progress_bus.publisher_for(job_id)                    (progress_bus.py:67)
        │  loop.call_soon_threadsafe(queue.put_nowait, event)
        ▼
asyncio.Queue                                         (one per SSE subscriber)
        │
        ▼
/api/training/jobs/{job_id}/events  (routers/training.py:79)
        │  "data: {json}\n\n"      +  ": keepalive\n\n" every 15 s
        ▼
streamTrainingEvents(jobId)  (services/api_client.dart:617)
        │  manual SSE parser (LineSplitter, ": heartbeat" filter, multi-line)
        ▼
TrainingController._handleEvent                       (training_provider.dart:201)
        │  if type=='epoch' → epochs.add(epochEvent) + epochTick++
        ▼
LossCurveChart repaint + PipelineStepper pulse
```

### 3.1 Backend — thread-safe pub/sub

`backend/app/services/progress_bus.py` is a tiny, dependency-free class:

- `subscribe(job_id)` (`:46`) returns an `asyncio.Queue`, registers it under
  the current loop.
- `publisher_for(job_id)` (`:67`) returns a closure that snapshots
  subscribers under a `threading.Lock` and dispatches via
  `loop.call_soon_threadsafe(queue.put_nowait, event)`. This is the only safe
  way to cross from the `run_in_executor` worker thread into the event loop.
- `close(job_id)` (`:88`) is called by `job_store` on terminal state and
  posts an `_STREAM_END` sentinel to each subscriber so the SSE generator
  exits cleanly.
- Heartbeats are emitted client-side by the SSE generator itself
  (`routers/training.py:131`) every 15 s using a 15 s `asyncio.wait_for`
  timeout on `queue.get()` — no traffic over the bus for heartbeats.

### 3.2 Adapter contract

`neurocnl/training/snntorch_adapter.py:135` is the gold-standard publisher
because it has direct per-epoch access:

```python
for epoch_index in range(n_epochs):
    ...
    loss_curve.append(loss_value)
    if progress is not None:
        now = time.monotonic()
        progress({
            "type": "epoch",
            "epoch": epoch_index + 1,
            "total_epochs": n_epochs,
            "loss": loss_value,
            "elapsed_seconds": now - start,
            "epoch_seconds": now - epoch_started,
        })
        epoch_started = now
```

`sleep_pes_adapter.py:150` works around a black-box `SleepOptimizer.train()`
that doesn't accept a per-epoch callback: it drains the full `loss_curve`
tuple at the end and **replays** synthetic events with `replayed: true` so
subscribers see the same wire shape. The Dart side does not currently
distinguish replayed events in the UI.

### 3.3 SSE stream hardening

- Late-attach replay: if the job is already in `JobComplete` or `JobFailed`
  state when the client subscribes, the generator yields the terminal event
  once and exits (`routers/training.py:101-122`).
- Reduced-motion: SSE `Cache-Control: no-cache`, `Connection: keep-alive`,
  `X-Accel-Buffering: no` headers (`routers/training.py:148-152`) — relevant
  for nginx in front of the backend.
- Dart side: `streamTrainingEvents` (`api_client.dart:617`) tolerates
  multi-line `data:` payloads (joins with `\n`), filters SSE comment lines
  starting with `:`, and discards decoded values that aren't `Map`.

### 3.4 Polling fallback

`TrainingController._startPolling` (`training_provider.dart:213`) runs a
`Timer.periodic(seconds: 2)` in parallel with the SSE stream. It guards
against re-entry with `_isPolling` and is cancelled the moment the SSE
`done`/`failed` event arrives (or vice versa). This means the UI can survive
a broken SSE connection (proxy timeout, reverse-proxy buffering) and still
flip to `success`/`failure` when `job_store` reaches a terminal state.

---

## 4. Post-training SNN playback animation

`frontend/lib/widgets/canvas/animated_snn_playback.dart` (1 088 lines) is the
largest animation widget in the repo. It is **not** training-specific — it
replays a completed simulation, and the same code path renders the trained
network's first forward pass.

### 4.1 Controls (`:78-87`)

- Play/pause, speed selector (`½×, 1×, 2×, 5×`),
- Scrubber slider, elapsed time label,
- Pinch-to-zoom (clamped 1×..20×), single-finger drag to pan when zoomed,
  double-tap to reset,
- `MediaQuery.disableAnimationsOf` honored throughout.

### 4.2 Wall-clock duration

`Duration get _wallDuration` at `animated_snn_playback.dart:81` scales the
simulation time so that `30 ms` of simulation plays back in ~`1 s` of wall
time, with a 4 s minimum so short sims are not a flash
(`_minWallSeconds = 4.0` at `:79`). The duration is recomputed when speed
changes so the cursor continues from the current `progress` value.

### 4.3 Three painters sharing one cursor

The widget tree is split into three `RepaintBoundary` subtrees (`:362`,
`:413`) so each `CustomPaint` is repainted independently when its
`AnimatedBuilder` ancestor ticks the single `AnimationController _controller`.

- **Firing-rate bars** (`_AnimatedFiringRateChart` `:592`) — 40 windows
  computed once via `_computeFiringRates` (`:231`). Each bar is an
  `AnimatedContainer` whose height transitions from 0 to
  `rate / maxRate * maxHeight` once the time cursor crosses the bar's window
  (`:678`). Color is `Color.lerp(primaryDim, primary, fraction)` so cooler
  dims correspond to quieter windows.
- **Spike raster** (`AnimatedRasterPainter` `:694`) — two-pass paint:
  horizontal grid + neuron labels, then per-neuron spike markers. Each spike
  is rendered as a bright violet outer glow (`BlendMode.screen` in
  `glowPaint` `:801`) and a primary-colored core, with a `_glowWindowMs =
  80` ms decay envelope. A 40-px-wide `LinearGradient` shadow trails the
  cursor leftward to give a DAW-style feel (`:846`).
- **Voltage chart** (`AnimatedChartPainter` `:892`) — adaptive sample step
  `step = max(1, visibleSamples ~/ 500)` (`:949`) so the path stays smooth
  at 1× zoom and degrades gracefully at 20× zoom when the visible window
  contains too many samples for 60 fps.

All three renderers share the time cursor (`currentTimeMs`) and zoom window
(`visibleRange`) by reading them off the same `AnimationController`, so the
user sees a single coherent timeline.

### 4.4 Reduced-motion fallback

`shouldRepaint` on both painters compares `reduceMotion` against the prior
value; the raster swaps the violet glow for a static 1.2 px dim circle
(`animated_snn_playback.dart:815`) and skips the cursor shadow
(`animated_snn_playback.dart:843`). Voltage traces still draw up to the
cursor with no animation.

### 4.5 Static sibling

`widgets/canvas/snn_dynamics_view.dart` is a non-animated version of the
same three views (firing rate + raster + voltages) for embedding in reports
or compare-style panels. The two widgets share `traceColorPalette` from
`widgets/canvas/time_series_chart.dart`.

---

## 5. Server-side matplotlib visualization

`neurocnl/visualization.py` (357 lines) ships matplotlib-based renderers for
spike raster, membrane voltage, network topology, and weight evolution.
Notable facts:

- Uses `matplotlib.use("Agg")` (`:22`) so it works headless in CI / containers.
- `to_html(fig)` (`:337`) base64-encodes the PNG into a single `<img>` tag,
  suitable for embedding in an HTML report or sending through JSON.
- `_check_matplotlib` (`:36`) raises a friendly `ImportError` pointing at the
  `neurocnl[viz]` extra when the dependency is missing.
- Weight evolution (`weight_evolution` `:279`) is the closest in spirit to a
  training-time chart (it shows how a STDP connection's weights evolve), but
  it requires the caller to pass a `weight_data` probe — no built-in
  integration with the training event stream exists.

This module is **orphaned from the live UI** — nothing under
`neurocnl/backend/app/routers/training.py` calls into it, and the in-app
training panel renders its own curve with `CustomPainter` instead. It is
useful for notebook and CLI workflows.

---

## 6. Shared UI primitive: `NmtkPipelineStepper` heartbeat

`nmtk_ui_core/lib/widgets/pipeline_stepper.dart:8-34` defines
`NmtkPipelineStepData` with a `pulseTick: int` field (default `0`). The
`didUpdateWidget` override at `:285-295` compares the prior and new
`pulseTick`, and on increment forwards `_pulseCtrl` from `0` to
`Curves.easeOut` (and back). The chip is then wrapped in
`Transform.scale(scale: _pulseScale.value)` at `:340`. The animation is
gated on:

1. `widget.data.status == NmtkStepStatus.running`,
2. `pulseTick > 0` (skips initial mount),
3. `!MediaQuery.disableAnimationsOf(context)`.

The widget is `nmtk_ui_core` (state-management-agnostic, per the module's
`AGENTS.md` constraint), so it accepts the `pulseTick` as plain data and
re-exposes it via the `epochPulseTick` named parameter on
`SnnWorkflowStepper` (`nmtk_ui_core/lib/widgets/snn_workflow_stepper.dart:31`).

---

## 7. What is *not* implemented (and where to find the gap)

### 7.1 No Results-step view

`docs/archive/2026-06-09-cnl-studio-workflow-advisory.md:91-101` recommends
moving the animated loss curve into a dedicated final "Results" step. The
current implementation still renders the curve inline inside the
`TrainingInspectorPanel` (which is mounted as a pipeline panel in
`studio_screen.dart:1291` and in the notebook step area at
`studio_screen.dart:140`). The Studio's notebook step at
`studio_screen_screen.dart:948-965` still treats `trainingSandbox` as the
final pre-`trainAndExport` step rather than a dedicated results surface.

### 7.2 Topology is invisible to training

`docs/current tasks/2026-05-24-nir-bundle-architecture.md:83-98` documents
that the current `SnnTorchAdapter` builds a hardcoded `TinySnn` topology and
ignores the user's CNL spec structure (`frontend/lib/widgets/training_inspector_panel.dart:158-181`
submits `n_epochs`, `dataset`, `spec` — but `spec` is only echoed in the
result's `metadata`, not used to shape the network). The visualization is
therefore accurate for the loss curve, but the resulting weights do not
correspond to the topology the user drew. This is not a visualization bug
per se, but it is the most likely reason a future user will look at the
"learned_weights" matrix and feel deceived.

### 7.3 No replayed-event distinction in the UI

`sleep_pes_adapter.py:150` flags synthetic epoch events with `replayed: true`,
and `TrainingEpochEvent.fromJson` (`training_provider.dart:39`) carries the
field, but `_Polling` and the chart ignore it. A user observing Sleep-PES
training sees the curve "draw itself" all at once after the job completes,
which is jarring compared to snnTorch's per-epoch streaming. A subtle
`replayed` badge in the loss chart's title would close this gap.

### 7.4 No weights / topology view

`TrainingResult.learnedWeights` is parsed by `models/training.dart:116-120`
but never rendered. `weight_evolution` in `neurocnl/visualization.py:279` is
the obvious server-side primitive; on the client side, the
`AnimatedSnnPlayback`'s `voltages` map could be extended to accept a weight
trace with the same `CustomPainter` treatment.

### 7.5 No comparison view across runs

`studio_screen.dart:1291` mounts the training panel as a `KeepAliveWrapper`,
but no second instance or side-by-side is supported. A "compare last two
runs" overlay (a second `LossCurveChart` with reduced opacity) is a small
change once the `trainingResultProvider` (`training_provider.dart:282`) is
extended to retain a history.

---

## 8. Quick reference: file → role index

| Concern | File | Anchor |
|---|---|---|
| SSE router | `neurocnl/backend/app/routers/training.py` | `:79` |
| Pub/sub bus | `neurocnl/backend/app/services/progress_bus.py` | `:37` |
| Job submit | `neurocnl/backend/app/services/training_service.py` | `:178` |
| snnTorch per-epoch publish | `neurocnl/neurocnl/training/snntorch_adapter.py` | `:144` |
| Sleep-PES replayed publish | `neurocnl/neurocnl/training/sleep_pes_adapter.py` | `:150` |
| Dart SSE parser | `neurocnl/frontend/lib/services/api_client.dart` | `:617` |
| Training Riverpod state | `neurocnl/frontend/lib/providers/training_provider.dart` | `:95` |
| Training state machine | `neurocnl/frontend/lib/widgets/training_inspector_panel.dart` | `:73`, `:236` |
| Live loss chart painter | `neurocnl/frontend/lib/widgets/canvas/loss_curve_chart.dart` | `:100` |
| Animated checkmark | `neurocnl/frontend/lib/widgets/training_inspector_panel.dart` | `:755` |
| Pipeline heartbeat primitive | `nmtk_ui_core/lib/widgets/pipeline_stepper.dart` | `:8`, `:285` |
| Studio wiring | `neurocnl/frontend/lib/screens/studio_screen.dart` | `:140`, `:1291` |
| Pipeline bar pulse wiring | `neurocnl/frontend/lib/widgets/pipeline_bar.dart` | `:52` |
| Studio top bar pulse wiring | `neurocnl/frontend/lib/screens/studio/studio_top_bar.dart` | `:63` |
| Post-run SNN playback | `neurocnl/frontend/lib/widgets/canvas/animated_snn_playback.dart` | `:32` |
| Static SNN view | `neurocnl/frontend/lib/widgets/canvas/snn_dynamics_view.dart` | `:20` |
| Server-side viz (orphaned) | `neurocnl/neurocnl/visualization.py` | `:1` |
| CLI matplotlib loss | `Neuro-Dream-Hand/neurodreamhand/learning/sleep_pes.py` | `:282` |

---

## 9. Conclusion

The training animation stack in NMTK is mature in three places:

1. **Live loss curve** — SSE → Riverpod → `CustomPainter`, with proper
   thread-safety, late-attach replay, polling fallback, and reduced-motion
   support.
2. **Pipeline chip heartbeat** — a one-line `pulseTick` increment drives a
   `Transform.scale` animation across two mounted instances (pipeline bar +
   top bar).
3. **Post-run SNN playback** — the largest and most polished piece
   (`AnimatedSnnPlayback`), with zoom/pan/scrub/glow trails.

The two biggest visible gaps are (a) the loss curve is still inline in the
training panel rather than in a dedicated Results step as the workflow
advisory recommends, and (b) the curve shows genuine loss values for
`snnTorch` but a single-shot replay for `sleep_pes` — a `replayed` badge
would make the distinction honest.
