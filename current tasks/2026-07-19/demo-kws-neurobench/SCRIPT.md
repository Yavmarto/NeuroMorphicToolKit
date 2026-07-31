# Recording Script (~3 minutes — MNIST result, Braille research, conditional Akida)

## Why this shape

This version removes keyword spotting from the video. The current KWS benchmark path is not
trustworthy enough for a portfolio claim, while the feed-forward MNIST FCN has a measured Studio
result of **92.45% test accuracy** and trains in five epochs.

The video uses three pieces of evidence for three different claims:

- **MNIST FCN:** the dependable end-to-end product demonstration.
- **Braille RNN:** the research and debugging story, using the presenter's latest **~85%** run.
- **Akida:** a pre-recorded hardware insert only if the exact physical-device path passes every
  gate below; otherwise show package generation and describe power figures as estimates.

The intended audience is a hiring manager or general portfolio viewer. Keep the central story on
what was built and what was measured; architecture details support that story instead of replacing
it.

## Recording gate — complete off camera

### MNIST evidence

Follow `current tasks/2026-07-28/GUIDE-mnist-fcn-studio.md` and capture:

1. The six-node `784 → 1000 → 10` feed-forward graph.
2. The generated architecture showing two LIF layers, 25 timesteps, and 794,000 parameters.
3. Five epochs of training with the validation result.
4. The Eval output line confirming that `best_model.pt` loaded.
5. The final test result.

Use **92.45%** in the narration only if the fresh recording remains close to that measured
baseline. If it differs materially, say the newly observed number and investigate before recording;
never reuse the old number over a contradictory screen.

### Braille evidence

Capture the result screen from the current ~85% run and one useful training plot. Keep the claim
narrow: this is a recurrent tactile-classification experiment reproduced in the Studio, not an
Akida-compatible network and not a reproduction of the stale 92% reference result.

### Akida hardware gate

Use the feed-forward MNIST network, never the recurrent Braille network. Record an
**on-hardware** insert only after all of these are visible in one rehearsed run:

1. Readiness identifies the Linux/Windows Akida host.
2. Runtime status identifies a physical Akida device, not `AkidaSimulator` or
   `software_fallback`.
3. The mapped artifact contains the intended trained or explicitly quantized weights, not only the
   untrained topology.
4. Device mapping completes.
5. Inference completes on fixed, saved inputs.
6. Post-quantization accuracy is measured and recorded.
7. Any energy value claimed as measured comes from non-null device telemetry with a known unit.

If any gate fails, use the fallback insert: **Check Readiness → Map Runtime → Generate Package**.
Narrate it as a deployment package or SDK handoff, not a completed chip run, and label
Neurochip's profile-based power/latency figures as **estimated**.

## Script — SHOW and SAY

### 0:00–0:15 — Open with the result

- **SHOW:** MNIST Eval result, then a quick cut to the graph.
- **SAY:** “This spiking network classifies handwritten digits at about ninety-two percent test
  accuracy. I built and trained it inside NeuroStudio, from the network graph through evaluation.”

### 0:15–0:35 — Frame the product

- **SHOW:** NeuroStudio's Model, Training, Eval, and Results steps.
- **SAY:** “Neuromorphic software is usually fragmented across model formats, simulators, and
  hardware tools. This toolkit puts the workflow in one place and keeps the network portable
  through NIR, the Neuromorphic Intermediate Representation.”

### 0:35–1:10 — Build the MNIST network

- **SHOW:** The six-node Model canvas; select each Linear and LIF layer, then toggle Canvas and NIR
  views.
- **SAY:** “This is deliberately simple and recognizable: 784 image pixels, a thousand-neuron
  spiking hidden layer, and ten output neurons. The visual graph compiles to NIR, so the same
  architecture can be inspected and handed to different runtimes without redrawing it.”

### 1:10–1:45 — Train and evaluate

- **SHOW:** Training DAG briefly, then a pre-recorded five-epoch progress sequence, best-checkpoint
  load, and final Eval result.
- **SAY:** “The training pipeline is also visual: data, state reset, forward pass, spike-count
  loss, surrogate-gradient backpropagation, optimisation, and validation. Five epochs reach about
  ninety-two-point-five percent on the held-out test set, and the evaluation explicitly reloads the
  best validation checkpoint.”

Do not run all five epochs live. Use a short pre-recorded insert so the viewer sees real progress
without dead time.

### 1:45–2:10 — Braille research story

- **SHOW:** Braille recurrent graph, training curve, and the current ~85% result.
- **SAY:** “I also reproduced a harder tactile Braille experiment using a recurrent spiking
  network. It reaches about eighty-five percent in my current run, and the valuable part was the
  engineering process: isolating unstable training changes, fixing weight-initialisation drift,
  and documenting a breaking snnTorch version difference instead of hiding it.”

- **SAY:** “This recurrent model is not compatible with the current Akida exporter, which requires
  a feed-forward chain, so I use the MNIST network for the deployment demonstration.”

### 2:10–2:40 — Akida, choose exactly one narration

#### Variant A — every physical-hardware gate passed

- **SHOW:** Physical device identity, successful mapping, inference output, and measured
  post-quantization accuracy; show power telemetry only when it passed the telemetry gate.
- **SAY:** “The feed-forward network also fits the current Akida deployment path. Here the app
  discovers the remote runtime, maps the quantized model to the physical device, and runs
  inference; after quantization it measured [INSERT VERIFIED ACCURACY] on the recorded test set.”
- **OPTIONAL SAY:** “The device reported [INSERT VALUE AND UNIT] during this run.”

#### Variant B — any physical-hardware gate failed

- **SHOW:** Readiness, mapped-network summary, and generated package; keep simulator or fallback
  labels visible.
- **SAY:** “The toolkit validates this feed-forward network for Akida and generates the deployment
  package for the remote SDK. I have not verified this exact trained artifact end to end on the
  physical chip, so the power and latency figures shown here are estimates, not measurements.”

Never combine the wording from both variants.

### 2:40–3:00 — Close

- **SHOW:** MNIST result, Braille result, and the final Akida status or package card side by side.
- **SAY:** “The result is one workflow for a measured feed-forward baseline, a genuinely difficult
  recurrent experiment, and an honest hardware handoff. The point is not that every network maps
  perfectly everywhere; it is that the toolkit makes the differences visible before deployment.”

## Editing notes

- Record each section as a separate take and keep all numeric evidence legible at 1080p or higher.
- Put **snnTorch test**, **Akida post-quantization**, **device measured**, or **estimated** directly
  beside every number so viewers never have to infer its source.
- Remove the Poisson million-neuron cold open and mobile segment from the main cut; they distract
  from the measured result and can be separate product clips.
- Do not show the KWS benchmark table, claim comparable KWS accuracy, or claim that activation
  sparsity proves measured energy.
- Do not say “same predictions” across simulator and Akida unless the recorded comparison actually
  establishes it.

## Final dry run

1. MNIST result is freshly reproduced and the best checkpoint visibly loads.
2. Every spoken number matches the visible result and is labelled with its execution target.
3. Braille is described as recurrent research evidence, not as Akida-deployable.
4. Exactly one Akida narration variant is selected.
5. A physical-hardware claim is used only when all seven hardware gates pass.
6. The finished cut is at or below three minutes and contains no KWS claim.
