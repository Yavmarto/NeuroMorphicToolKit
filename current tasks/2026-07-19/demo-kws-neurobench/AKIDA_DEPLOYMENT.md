# Akida recording gate for the MNIST FCN

This guide determines whether the video may claim physical Akida inference. It replaces the former
KWS deployment instructions and deliberately separates topology compatibility, package generation,
SDK mapping, physical execution, accuracy, and energy evidence.

## Compatibility decision

- **MNIST FCN:** eligible for rehearsal because its topology is one feed-forward chain.
- **Braille RNN:** not eligible because its recurrent `RSynaptic` path introduces a cycle.
- **Akida semantics:** approximate for this model because LIF nodes become quantized,
  fused-activation Akida layers rather than literal integrate-and-fire dynamics.

The mapped payload preserves LIF threshold and membrane-time-constant metadata, but the current
Akida construction path does not use those fields to reproduce the original neuron dynamics.
Therefore snnTorch accuracy and Akida accuracy are separate measurements.

## Environment requirements

- Use the paired Linux or Windows host with the physical AKD1000 and Akida SDK.
- The selected runtime must report a physical device identity.
- `AkidaSimulator`, `software_fallback`, package generation, or an SDK-ready status alone do not
  count as physical execution.

Use only the Studio's in-app deployment flow:

**Results → Deploy to Hardware → Akida → Check Readiness → Map Runtime → Generate Package or
Install → Run Inference**

## Gate 1 — readiness

Pass only when the selected host is reachable and the runtime response identifies:

1. A supported host runtime.
2. The Akida SDK as available.
3. A physical Akida device.
4. No simulator or software-fallback target.

If this gate fails, record the package-only fallback and stop making hardware claims.

## Gate 2 — artifact identity

Before mapping, confirm the artifact represents the trained MNIST model:

1. The topology is `784 → 1000 → 10`.
2. Layer dimensions match the trained Studio model.
3. The deploy artifact contains the intended trained or explicitly quantized weights.
4. The artifact is not merely a scaffold built from randomly initialised Model-canvas weights.

The existence of `best_model.pt` proves that Studio evaluation can reload a trained checkpoint; it
does not by itself prove that the Akida package contains those checkpoint weights. If weight
identity cannot be established, use the package-only narration.

## Gate 3 — mapping and inference

Pass only when:

1. Device mapping completes without falling back to the simulator.
2. Inference completes on a saved, reproducible input set.
3. The response comes from the physical runtime identified in Gate 1.
4. Outputs are retained with the inputs so the run can be repeated.

Do not describe a successful readiness check or mapping call as inference.

## Gate 4 — post-quantization accuracy

Run the recorded evaluation inputs through the physical artifact and compute accuracy separately
from the 92.45% snnTorch baseline. Put both labels on screen:

| Execution target | Accuracy |
|---|---:|
| snnTorch test baseline | freshly reproduced value |
| Akida physical, post-quantization | freshly measured value |

Do not say “same predictions” unless a sample-by-sample comparison supports that statement. Do not
quote 92.45% as Akida accuracy merely because the unquantized snnTorch model achieved it.

## Gate 5 — energy wording

Use **measured** only when the physical model's runtime telemetry returns a non-null energy or power
value and its unit is known. Record the raw device response alongside the displayed value.

Values derived from `Neurochip/neurochip/targets/akida.json`, energy-per-operation constants, or
network topology are **estimated**. They may be useful for comparison, but they are not a chip
measurement.

## Allowed recording outcomes

### Outcome A — verified physical execution

All five gates pass. The video may show and say:

- Physical Akida device identity.
- Successful device mapping and inference.
- The measured post-quantization accuracy.
- Device-reported power or energy only when Gate 5 passes.

### Outcome B — package-only fallback

Any gate fails. Show:

- Readiness result.
- Feed-forward compatibility verdict.
- Mapped-network summary.
- Generated deployment package.

Say that the toolkit prepared the model for the remote Akida SDK, that this exact trained artifact
was not verified end to end on the physical chip, and that displayed power or latency values are
estimates.

## Final sign-off

Before choosing Outcome A, verify all of the following in the captured take:

- Physical device identity is visible.
- No simulator or software-fallback label appears.
- Trained-weight identity is established.
- Mapping and inference both succeed.
- Post-quantization accuracy is recorded.
- Every energy value is identified as device-reported or estimated.

If one item is missing, choose Outcome B.
