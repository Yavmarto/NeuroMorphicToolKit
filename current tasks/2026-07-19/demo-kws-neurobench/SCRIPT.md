# Recording Script (~3.5 min hybrid — live + pre-baked inserts, mobile on physical Android)

## Why this shape
KWS is the wrong thing to *train live* (real Speech Commands training takes minutes); it's the right
**credibility finale**. The live, zero-dead-air beats use **`cpg_rhythm`** — it compiles today, previews
near-instantly (Nengo, 500ms cap, decoder-cached), and its mutual-inhibition oscillation is striking in the
animated raster. Verified:
- Live-simulatable specs are in **`neurocnl/backend/app/templates/`** (16 compile). `examples/` and
  `Neurohub/shared_assets/` mostly throw `legacy_grammar` — **don't load those on camera.**
  Confirmed compiling heroes: `cpg_rhythm` (6n), `reflex_arc` (5n), `looming_detector` (5n).
- Cold-open eye-candy: Poisson **chip-die viz** (`viz_demo_screen.dart`) — ~1M-neuron tile grid, instant,
  **keep slow (photosensitivity-throttled ~4.5fps default)**.
- Mobile: **Neurobench is hidden on mobile**; canvas is touch-ready; physical Android needs a LAN host.

## Pre-flight (before recording — off camera)
1. **Backends up:** `docker compose up -d`; `curl -s localhost:8000/health` → `{"status":"ok"}`; demo routes
   on (`NMTK_DEMO_ROUTES=true`, dev default).
2. **Desktop launcher:** `make dev` (or `cd nmtk/neuro_toolkit && flutter run -d macos`).
3. **Pre-bake insert A (KWS benchmark):** train `neurocnl/examples/keyword_spotting.cnl` offline via the
   Train canvas / Jupyter worker, run the Neurobench `keyword_spotting` benchmark, capture the
   results-vs-published table (fill `results_vs_baseline.md`).
4. **Pre-bake insert B (hardware):** export the trained NIR (`neurocnl/neurocnl/export/…`) → deploy to your
   board via the matching Neurochip route → capture on-hardware inference + energy.
5. **Physical Android:** phone on the SAME Wi-Fi; get host LAN IP (`ipconfig getifaddr en0`); backend binds
   `0.0.0.0`. Pre-build so the phone is already on the canvas screen:
   `flutter run -d <device> --dart-define=NMTK_CONTROL_API_BASE_URL=http://<LAN-IP>:8090 --dart-define=SUITE_API_URL=http://<LAN-IP>:9000`
6. Have `cpg_rhythm` ready (paste or template picker). Clean desktop, mic check, recorder 1080p+.

## Script — SHOW (do) / SAY (narrate)

### 0:00–0:20 Cold open (live)
- **SHOW:** Poisson chip-die viz (`viz_demo_screen`), high scale, slow playback, full-screen shimmer.
- **SAY:** "This is a spiking neural network with about a million neurons, running as an event-driven
  simulation. Neuromorphic computing is fast and low-power because, like the brain, almost nothing fires at
  once. The problem is it's hard to design. I built a toolkit that fixes that."

### 0:20–0:35 Frame (live → launcher home)
- **SHOW:** NMTK launcher catalog / NeuroStudio landing.
- **SAY:** "You design the network in plain English, watch it become a runnable graph, simulate it, and
  export it to real neuromorphic chips — all in one place."

### 0:35–1:25 Design in plain English + tri-view (live — THE headline)
- **SHOW:** NeuroStudio → Model canvas → CNL panel. Paste `cpg_rhythm`. Point at two lines. **Validate**
  (passes) → **Sync to Canvas** (nodes appear).
- **SAY:** "I'm describing a central pattern generator — two neuron populations, an extensor and a flexor,
  that inhibit each other. Watch: 'Define a LIF neuron named extensor…', 'flexor connects to
  w_flexor_extensor', which loops back. That's the recurrent inhibition that creates rhythm."
- **SHOW:** Toggle view mode **CNL → NIR → Canvas** (`StudioViewMode`). Same graph, three forms.
- **SAY:** "The English compiles to NIR — the Neuromorphic Intermediate Representation the whole field is
  standardizing on — and the graph, the text, and the IR are the same object. Edit one, the others update."

### 1:25–2:05 Simulate live (live — payoff)
- **SHOW:** Simulate surface → **Run**. Animated raster / dynamics view (`animated_snn_playback`,
  `snn_dynamics_view`) reveals spikes as the cursor sweeps. Scrub. Point at alternating extensor/flexor
  bursts.
- **SAY:** "No training needed for this one — the structure does the work. Run it, and the oscillation
  emerges: the two populations take turns firing. Top panel is firing rate, middle the spike raster, bottom
  membrane voltage — cause and effect, side by side. This ran in well under a second."

### 2:05–2:35 Credibility: keyword spotting (live spec + PRE-BAKED insert A)
- **SHOW:** Briefly load `keyword_spotting.cnl` (deeper net). Cut to insert A: Neurobench
  results-vs-published table.
- **SAY:** "Toy demos are easy, so here's a real one: keyword spotting on Google Speech Commands — a
  published NeuroBench benchmark. I trained it in the toolkit and benchmarked it against the paper.
  Comparable accuracy — and here's the point of neuromorphic: the activation sparsity and synaptic-operation
  count, the energy story."

### 2:35–3:00 Hardware (PRE-BAKED insert B)
- **SHOW:** Insert B: NIR export → Neurochip deploy → on-hardware inference + energy readout.
- **SAY:** "Same network, one export, and it runs on actual neuromorphic silicon — same predictions, real
  measured energy. Design to chip without rewriting anything."
- **HONEST LINE (say it):** "Everything spiking here is LIF, which maps cleanly to every backend; the
  numbers I trust most are the simulator and on-hardware runs."

### 3:00–3:20 Mobile (live, physical Android)
- **SHOW:** Cut to the phone (already on the canvas). Pinch-zoom, drag a node, tap **Run**, show the raster
  on the touch screen.
- **SAY:** "And it's the same app on a phone — the canvas is fully touch-driven, talking to the same backend
  over the network. Design and simulate spiking networks from anywhere."

### 3:20–3:35 Close (live)
- **SHOW:** Back to tri-view or chip-die viz.
- **SAY:** "Plain English to a standard IR, live simulation, published-benchmark results, and real hardware
  deployment — one toolkit. Thanks for watching."

## Tips
- Record each segment as its own take; stitch in edit. Live beats + the two inserts are independent.
- Keep the chip-die viz slow on camera (seizure-safety + reads better).
- If `Sync to Canvas` errors live, you loaded a non-template spec — use only
  `neurocnl/backend/app/templates/*.cnl`.
- Pre-load the phone build; keep host + phone on one Wi-Fi.

## Dry-run before the real take
1. `cpg_rhythm` → Validate passes → Sync populates → tri-view toggles all show the graph.
2. Run preview → animated raster shows alternating bursts in < 1s.
3. Chip-die viz streams at the slow rate.
4. Phone connects (canvas loads, Run returns a raster) via the LAN-IP dart-defines.
5. Inserts A and B captured and legible at 1080p.
