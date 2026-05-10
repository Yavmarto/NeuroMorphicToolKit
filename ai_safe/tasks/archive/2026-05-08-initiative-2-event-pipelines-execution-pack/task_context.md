# Goal

Implement the requested behavior using only the sanitized context in this packet.

# Deliverable

Return a unified diff or a small set of unified diffs against the provided stub files.

# Task Summary

Implement a coherent first execution slice for standardized event-data pipelines. This slice should stop short of building every dataset integration or every downstream consumer, but it should make the event-input path honest, deterministic, and reusable. The key behaviors are:

- deterministic event-to-address mapping
- deterministic relative timestamp handling
- dense spike-tensor binning for event batches
- shared validation for event coordinates and timestamp ordering
- a canonical payload builder that preserves backward-compatible fields while surfacing the new binned tensor output
- focused unit coverage for exact acceptance examples and fail-closed cases

The intent is to give the local repository a stable event-batch foundation that later dataset loaders, replay paths, and benchmark hooks can build on.

# Required Semantics To Mirror

- Event records use exactly these logical fields:
  - `x`
  - `y`
  - `polarity`
  - `timestamp_us`
- The flattened neuron address is exactly:
  - `address = y * (width * 2) + x * 2 + normalized_polarity`
- `normalized_polarity` is `1` when polarity is positive and `0` otherwise.
- Relative timestamps are computed from the first event in the batch.
- Time-bin index is `relative_timestamp_us // bin_width_us`.
- Multiple events may accumulate in the same bin and same address; the tensor stores counts, not booleans.
- Out-of-bounds coordinates fail closed.
- Non-monotonic event timestamps fail closed.
- Non-positive bin width fails closed.
- Empty input is valid and returns an empty tensor plus empty summary lists.
- Backward-compatible payload fields should remain available if they already existed:
  - `addresses`
  - `timestamps`
  - `counts`
  - `shape`
- The new payload may add:
  - `relative_timestamps_us`
  - `n_bins`
  - `spike_tensor`

# What You Are Allowed To Use

- Only the files and interfaces included in this packet
- Python standard library
- `numpy`

# What You Must Not Assume

- Hidden tensor libraries exist
- Sparse matrix helpers exist
- Real dataset SDKs are available
- The task includes adding every event dataset integration now
- Automatic clipping or automatic sorting is acceptable for invalid input

# Required Output Format

Use this exact structure:

## Assumptions

- List any assumption that was necessary.

## Implementation

Provide the patch or patches.

## Validation Notes

- Explain how the implementation satisfies the examples and constraints.

## Open Questions

- List only questions that block correctness.

# Completion Criteria

- Event validation, address mapping, and spike-tensor binning are deterministic.
- The canonical event payload includes the required summary fields.
- Backward-compatible fields remain present.
- The implementation stays within the scoped event-pipeline slice and does not invent broader architecture.
- The response does not request broader repository context unless correctness is impossible.
