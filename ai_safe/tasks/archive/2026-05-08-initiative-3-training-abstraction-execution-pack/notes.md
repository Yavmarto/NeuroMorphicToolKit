# Reintegration Notes

- This packet is a larger implementation pass for Initiative 3, not the full training abstraction initiative.
- Intended local reintegration area is the `neurocnl` library surface, near existing backend capability and planning logic.
- A strong result should return one or more patches that:
  - add a small registry module
  - keep adapter selection and dispatch deterministic
  - add focused unit coverage
  - avoid any real framework imports

Local repo-grounding still required after Deerflow returns:

1. Compare the returned patch against the real `neurocnl` package layout.
2. Decide whether the registry should stay internal or become a public library surface.
3. Preserve alignment with existing backend capability terminology.
4. Run the local tests for the touched registry module.

Suggested local verification after reintegration:

- targeted pytest for the new registry test file
- broader `neurocnl` library checks only if the patch touches shared capability surfaces

# Sanitization Notes

- Backend names in the examples are neutral placeholders, not commitments to specific framework wiring.
- No external framework SDKs, proprietary workflow details, or hidden architecture notes are included.
- This packet intentionally avoids asking Deerflow to implement real training execution in the same pass.
