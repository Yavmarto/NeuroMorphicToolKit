# PYNQ/FPGA pipeline generalization — follow-up notes

Context: this session wired a real `deploy_payload` into
`POST /api/deploy/pynq/network` (see
`current tasks/2026-07-23/studio-e2e-demo-walkthrough.md` and the code changes
in `neurocnl/neurocnl/export/pynq_exporter.py`, `neurocnl/planner.py`,
`neurocnl/backend/app/routers/deploy.py`). That fix makes today's PYNQ path
work — but it's still a bespoke, fixed overlay-v1 MMIO contract
(`neurocnl/neurocnl/contracts/pynq_deployment_contract.py`'s `PYNQ_LIMITS`):
one hardcoded board, one hardcoded register map, one hardcoded weight layout.
Adding a second FPGA board today means writing a whole new exporter/contract
module from scratch, same as PYNQ's.

## The generic path

`snn-mlir` (github.com/INTERA-GROUP/snn-mlir, vendored as a Docker service —
`workers/snn_mlir_compiler/`, port 8007, built from source in
`workers/snn_mlir_compiler/Dockerfile`) already provides exactly the piece
that's missing: a documented, extensible "implementing a new lowering pass"
path (`SNNToMyBackend`-style), a working CPU backend (`SNNToLinalg` → LLVM
IR), quantized IR support, and C-runtime codegen. NeuroCNL can already emit
its quantized SNN-MLIR IR (`neurocnl/neurocnl/generation/snn_mlir_generator.py`).

Recommended direction (not implemented this session — this is weeks of
compiler + hardware work):

1. Add a new lowering pass in `snn-mlir` (e.g. `SNNToAXI`/`SNNToHLS`) that
   consumes the quantized SNN-MLIR IR and emits an HLS/AXI-stream kernel +
   DMA packaging, generically — not board-specific.
2. Parameterize the board-specific constants (clock, neuron/synapse capacity,
   AXI width, DMA config) from the per-board JSON descriptors that **already
   exist and are currently unused for this purpose**:
   `Neurochip/neurochip/targets/pynq_z2.json`, `loihi2.json`, `speck2.json`,
   `teensy41.json`, etc. Today's `PYNQ_LIMITS` hardcodes the same kind of data
   inline in Python instead of reading it from there.
3. Wire the backend deploy endpoints to call the snn-mlir worker (already
   running as a service, just needs a client) for the lowering/codegen step,
   instead of each target having its own from-scratch exporter. Feed the
   result into the existing (already Nengo-free) handoff builders
   (`neurocnl/neurocnl/handoff/neurochip_pynq_handoff.py` and siblings) the
   same way this session's PYNQ fix does.
4. A new board then needs: a JSON descriptor + a board-specific
   Vivado/Vitis packaging shim reusing the same generic HLS/AXI kernel output
   — not a new bespoke exporter module per board.

This is materially different from — and lower-risk than — the FINN dataflow
approach already evaluated and rejected in
`neurocnl/docs/PYNQ_FINN_Integration_Plan.md` (FINN targets feedforward-CNN
dataflow, a poor structural fit for SNNs). snn-mlir's IR is SNN-native from
the start and already documents this exact kind of backend extension point,
so it doesn't carry the same "force an SNN into a CNN compiler" risk that
ruled out FINN.

## Related existing docs

- `neurocnl/docs/PYNQ_FINN_Integration_Plan.md` — original Phase 1
  (direct-MMIO overlay, what exists today) vs. Phase 2 (FINN, rejected/deferred)
  analysis.
- `neurocnl/issues-archive/005-pynq-finn-compilation-pipeline.md` — open
  issue tracking the FINN-based approach; the snn-mlir path above is an
  alternative to that ticket, not an implementation of it.
- `neurocnl/docs/support_matrix.md` — current PYNQ support-tier status.

## Known residual gap not covered by this session's fix

`neurocnl/planner.py`'s `_estimate_synapse_count()` does dense
`pre_size * post_size` expansion per connection with no exclusion for I/O
port populations (`PORT_POPULATION_TYPES` in `neurocnl/neurocnl/ir/types.py`).
A network with a large input port (e.g. a 784-pixel image input feeding a
small hidden layer) could still trigger a spurious `EXCEEDS_SYNAPSE_CAPACITY`
rejection for PYNQ/Teensy, the same class of bug this session fixed for the
population-count and neuron-model checks. Left alone deliberately: whether an
input/output projection's weights should count toward on-chip synapse-memory
capacity is a real hardware-semantics question (they may consume real weight
memory on some targets, e.g. Teensy, even though overlay-v1 drops them
entirely), not a clear-cut bug fix like the ones made this session.
