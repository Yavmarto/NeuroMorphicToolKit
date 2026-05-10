# Reintegration Notes

- This packet is the route-contract slice only.
- A strong result will introduce a small shared error-payload helper or equivalent localized normalization.
- Local repo-grounding should verify that targeted frontend consumers can tolerate the normalized structured payloads.

Local repo-grounding still required after Deerflow returns:

1. Check every targeted route against the real FastAPI schemas.
2. Verify no tests depend on the old plain-string parse failure details.
3. Decide whether any route must preserve backward-compatible `messages` alongside richer `items`.

Suggested local verification after reintegration:

- targeted backend route tests
- parse, validate, generate, export, deploy route tests that assert payload shape

# Sanitization Notes

- Real route filenames are mentioned because the work is route-contract-specific and the names themselves are not sensitive.
- No production data, secrets, or internal logs are included.
