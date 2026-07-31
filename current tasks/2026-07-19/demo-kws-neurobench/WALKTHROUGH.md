# Demo walkthrough: MNIST FCN, Braille research, and conditional Akida

This walkthrough replaces the former keyword-spotting demo. KWS remains useful future work, but its
current dataset, benchmark, and Results integration are not reliable enough to support a portfolio
claim.

Use these sources:

- `current tasks/2026-07-28/GUIDE-mnist-fcn-studio.md` for the exact MNIST Model, Training, Eval,
  and Results configuration.
- `current tasks/2026-07-18/braille-replication-handoff.md` for the Braille history and research
  caveats.
- `SCRIPT.md` for shot order and narration.
- `AKIDA_DEPLOYMENT.md` for the evidence gate that determines which Akida narration is allowed.

## 1. Prepare the MNIST result

Build the exact feed-forward network from the MNIST guide:

`Input(784) → Linear(1000,784) → LIF(1000) → Linear(10,1000) → LIF(10) → Output(10)`

Use the guide's verified configuration: 25 timesteps, batch size 128, Adam at `0.0005`, CE Count
Loss, fast-sigmoid surrogate slope 25, and five epochs. Do not add gradient clipping, a scheduler,
or spike regularisation.

Before accepting the run:

1. Confirm the generated network reports 794,000 parameters.
2. Confirm both LIF layers use beta `0.95`.
3. Confirm training uses five epochs and learning rate `0.0005`.
4. Confirm Eval prints `Loaded best checkpoint from best_model.pt`.
5. Record the newly observed validation and test accuracy.

The prior measured baseline is 92.45% test accuracy on the documented 2,000-sample test subset.
Treat it as a reproducibility target, not a number to force into the video.

## 2. Prepare the Braille research insert

Use the latest successful Braille run, currently reported at approximately 85%. Capture:

1. The recurrent architecture.
2. One training or validation plot that shows the run's behaviour.
3. The final test result.

Describe the result as a current-run outcome. The original notebook's 92% figure is not a valid
current target because its recurrent snnTorch code crashes under the installed snnTorch 1.0.0
behaviour.

Do not send Braille to Akida. Its recurrent `RSynaptic` connection creates a cycle, and the shared
Akida mapper requires one strict feed-forward path.

## 3. Prepare the Akida insert

Use the MNIST topology because it is feed-forward. Follow `AKIDA_DEPLOYMENT.md` and decide the
recording outcome from evidence:

- If every physical-device gate passes, capture physical identity, mapping, inference,
  post-quantization accuracy, and any valid device telemetry.
- If any gate fails, capture readiness, the mapped-network summary, and package generation.

Package generation is a legitimate product capability, but it is not proof that the trained model
ran on a chip. Likewise, profile-based energy and latency values are estimates.

## 4. Record in this order

1. MNIST test result.
2. NeuroStudio workflow overview.
3. MNIST Model canvas and NIR view.
4. Pre-recorded MNIST training and Eval.
5. Braille recurrent research insert.
6. Exactly one Akida outcome: verified physical inference or package-only fallback.
7. Evidence-labelled closing frame.

The MNIST and Braille sections are independent of Akida readiness, so record them first. A hardware
problem should downgrade only the Akida wording, not derail the whole video.

## 5. Acceptance checklist

- The video is no longer than three minutes.
- No KWS accuracy, NeuroBench comparison, or Speech Commands result appears.
- The visible MNIST number matches the narration.
- The Braille number is labelled as the current run.
- Braille is never described as Akida-compatible.
- Akida simulator, software fallback, and physical hardware are never conflated.
- Post-quantization accuracy is shown before claiming useful on-chip inference.
- Energy is called measured only when physical-device telemetry returned a value with a known unit.
- Otherwise the video explicitly says package generation and estimated power/latency.

No app restart is required for these documentation changes. When preparing the actual recording,
launch the current app normally and use its in-app Setup and update paths rather than adding
terminal steps to the end-user story.
