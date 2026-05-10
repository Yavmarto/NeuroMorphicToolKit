# Constraints

## Allowed Dependencies

- Python standard library
- Existing framework dependencies already implied by the interfaces

## Behavior Rules

- Do not redesign the parser.
- Do not redesign the validator.
- Do not add network calls, persistence, or telemetry.
- Preserve fail-closed behavior.
- Prefer returning structured `detail` payloads over plain concatenated strings when the route already returns JSON error details.
- Preserve `hint`, `examples`, `line`, and `raw` when those fields already exist.
- If a route must summarize multiple parse failures, include the structured failures as items rather than only flattening to message strings.

## Scope Rules

- Limit the patch to route-level and small helper-level diagnostics plumbing.
- Do not redesign frontend consumers in this slice.
- Do not change successful response payloads unless needed for consistency with the error contract.
- Do not broaden this into a full shared exception framework for the whole application.

## Style Rules

- Prefer a small shared helper over repeated ad hoc payload shaping.
- Keep control flow explicit.
- Add comments only where the contract-preserving behavior is non-obvious.

## Safety Rules

- If a targeted route currently uses a string detail for non-parse failures, only normalize it when the semantics are clear.
- If exact compatibility is uncertain, preserve the existing status code and fail-closed meaning.

## Output Rules

- Return unified diffs.
- State whether the repo-mirroring semantics were followed exactly.
