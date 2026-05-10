# Constraints

## Allowed Dependencies

- Python standard library
- `pydantic`
- `requests`

## Behavior Rules

- Do not change the existing public signatures in:
  - `resources.py`
  - `models.py`
  - `neurocnl_client.py`
  - `control_plane.py`
  - `control_plane_models.py`
- Keep all new code under `tools/nmtk_mcp_server/`.
- The boilerplate must be deterministic and local.
- Use real resource paths and real route paths only from this packet.
- Do not introduce shell execution, subprocess calls, or background daemons.
- Do not implement actual device deployment.
- Do not classify deployability into final production verdicts beyond a placeholder typed scaffold.
- Do not invent stronger backend support semantics than the support matrix and existing validation responses imply.
- Treat the server layer as a blueprint/registry assembly, not a concrete runtime binding.
- Prompts must reference resources by URI or symbolic name instead of embedding long docs inline.
- State persistence must be append-oriented or file-oriented JSON helpers under a caller-provided base directory; do not hard-code machine paths.

## Style Rules

- Prefer small pure helpers.
- Use dataclasses or Pydantic models for typed metadata.
- Add brief comments only where control flow would otherwise be unclear.
- Prefer explicit names over clever abstractions.

## Safety Rules

- Do not add network calls to unknown endpoints.
- Do not hide missing semantics behind fake success values.
- If a behavior is not specified, scaffold it with an honest placeholder type or narrow helper rather than inventing production rules.
- Preserve fail-closed behavior for unsupported or unconfigured actions.

## Output Rules

- Return a unified diff.
- If a requested behavior cannot be completed without inventing semantics, implement the safe boilerplate subset and list the limit in assumptions.
- Validation notes must explicitly say that Phase 4 remains out of scope.
