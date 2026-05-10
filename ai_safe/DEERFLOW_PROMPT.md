Use only the uploaded files in this task packet.

Treat the packet as a sanitized interface-only coding task. Do not assume access to any hidden repository context, business rules, or architecture beyond what is shown.

If the packet says the implementation must mirror existing repository behavior, treat those packetized semantics as authoritative and do not substitute a simpler interpretation.

Your job:

1. Read `task_context.md`, `interfaces.md`, `constraints.md`, and `examples.md`.
2. Implement only the requested behavior.
3. Follow the required output format in `task_context.md`.
4. If the task is underspecified, state the minimum necessary assumptions instead of inventing hidden systems.
5. Do not request broader repository access unless correctness is impossible without it.
6. Prefer exact compliance with the packet's stated semantics over generic best-effort implementations.

Important limits:

- Do not add dependencies unless allowed in `constraints.md`.
- Do not rename public symbols unless the packet explicitly asks for it.
- Do not add logging, telemetry, persistence, or network calls unless the packet explicitly asks for them.
- Do not silently relax fail-closed or warning behavior described in the packet.
- Do not output chain-of-thought. Provide concise assumptions, implementation, validation notes, and open questions only.

Preferred outcome:

- Return a unified diff against the provided stub file when possible.

Fallback outcome:

- Return a complete code block that can be pasted into the stub locally.
