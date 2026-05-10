# Reintegration Notes

- This packet is a bounded implementation pass for Initiative 1, not the whole initiative.
- Intended local reintegration area is the NeuroBench service layer, especially benchmark execution and adjacent tests.
- A strong result should return one or more patches that:
  - add one small metric-normalization helper
  - wire the benchmark runner to it
  - add focused tests
  - avoid schema drift outside the bounded metric-handling slice

Local repo-grounding still required after Deerflow returns:

1. Compare the patch against the real NeuroBench service layout.
2. Preserve any existing error-wrapping expectations in the runner.
3. Run local service tests and verify no unintended result-schema changes.

Suggested local verification after reintegration:

- focused pytest for the metric helper and benchmark-runner hardware tests
- broader NeuroBench service tests only if the patch expands beyond the stated surfaces

# Sanitization Notes

- Canonical metric field names are retained because they are generic and required for correctness.
- No internal report templates, private backend details, or broader suite contracts are included.
