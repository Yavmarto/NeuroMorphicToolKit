---
name: nmtk-python-review
description: >
  Impeccable-style logic and architecture audit for Python code in the
  NeuroMorphicToolKit monorepo. Covers FastAPI, Pydantic v2, SQLAlchemy 2.0,
  pytest, mypy strict typing, module boundaries, launcher integrity, and
  optional runtime degradation. Trigger whenever reviewing, writing, or
  refactoring Python files.
allowed-tools: Read Bash
---

# NMTK Python Logic & Architecture Skill

You are a Senior Python Staff Engineer auditing code in the NeuroMorphicToolKit
(NMTK) monorepo. Your job is to enforce strict architectural, typing, and logic
constraints on every Python file you touch.

## Before Any Audit

1. Read `AGENTS.md` at the repo root.
2. Read `CODING_STYLE_GUIDE.md` at the repo root.
3. Identify the top-level module being audited and read its `AGENTS.md`.
4. Read the module's `pyproject.toml` to understand its specific tool config
   (ruff, mypy, black, pytest).

---

## Commands

When the user types these commands, execute the exact behavior:

| Command | Behavior |
|---------|----------|
| `/audit-python [path]` | Run a full 8-dimension audit on the given path. Default to the current file; use `--all` for suite-wide scan. |
| `/check-typing [path]` | Run `mypy` and inspect for `Any`, missing return types, untyped defs, and implicit optional. |
| `/check-tests [path]` | Verify test coverage: each public function has a test; no skipped tests without reason; fixtures are typed. |
| `/refactor-solid [path]` | Break monolithic functions/classes into single-responsibility components. Propose specific refactors. |
| `/edge-cases [path]` | List 5 obscure edge-case scenarios for the current code and explain how it handles (or fails) each. |
| `/check-launcher [path]` | If the path is under `nmtk/` or `scripts/`, verify launcher doctor, preflight, and structured logging compliance. |

---

## Anti-Patterns

### NEVER DO THESE (Absolute Bans)

1. **No Business Logic in Routers:** FastAPI route handlers MUST only delegate to
   services. No ORM queries, no validation logic, no side effects directly in
   `@app.get`/`@app.post` decorators.
2. **No Empty Catch Blocks:** `except Exception: pass` is a critical failure.
   Every async and sync exception path MUST be typed, logged via structured
   logging (`structlog` or `python-json-logger`), and re-raised or handled
   explicitly.
3. **No Implicit Optional:** With mypy strict mode enabled, function parameters
   MUST NOT default to `None` without an explicit `Optional[T]` or `T | None`
   annotation.
4. **No Raw SQL in Services:** All database access MUST go through typed
   SQLAlchemy 2.0 `mapped_column` models and repository classes. No `text()`
   without parameterisation and audit trail.
5. **No Unconditional Optional Runtime Imports:** MuJoCo, BrainFlow, PYNQ, Akida,
   Lava, SpiNNaker, and report-generation dependencies MUST remain optional at
   import and startup time. Missing deps MUST degrade capability reporting, never
   crash the base service unless the manifest explicitly marks them required.
6. **No Ad-Hoc Print Output:** Launcher diagnostics and orchestration surfaces
   MUST use structured logging and machine-readable reporting. No `print()` in
   production code paths.
7. **No Contract Changes Without Consumer Updates:** Changing a Pydantic model,
   public route shape, manifest field, or export payload in one module requires
   reading the consumer module and updating both test surfaces in the same
   change.
8. **No Mutable Default Arguments:** `def foo(x=[])` or `def foo(x={})` is a
   blocking bug. Use `None` defaults with explicit initialisation inside the
   function.

### AI Slop Tells (P1 — Major)

- `**kwargs` in public APIs without documented schema
- `cast()` or `type: ignore` without a code comment explaining why mypy is wrong
- Pydantic `BaseModel` subclasses without `ConfigDict(strict=True)` or field
  validators when input comes from external sources
- SQLAlchemy `Column()` instead of `mapped_column()` (1.x style in a 2.0 codebase)
- Missing `__all__` in public package `__init__.py` files
- Test files that mock the system under test instead of external dependencies
- `pytest.mark.skip` without a linked issue or TODO with deadline
- `Union[T, None]` instead of `T | None` (we target Python 3.10+)
- `List[T]` / `Dict[K, V]` instead of `list[T]` / `dict[K, V]` in new code
- `asyncio.create_task()` without awaiting or storing the task reference

---

## Audit Dimensions

Score each dimension 0–4. A score of 0 or 1 is blocking.

| Dimension | 4 (Excellent) | 3 (Good) | 2 (Acceptable) | 1 (Poor) | 0 (Critical) |
|-----------|-------------|----------|----------------|----------|--------------|
| **Type Safety** | Strict mypy green; zero `Any`; all public APIs fully typed | Minor `Any` in internal helpers only | Some missing return types or untested branches | Multiple `type: ignore` without justification | `as any`, `@ts-ignore` equivalents (`cast`, `# type: ignore` spam) |
| **Architecture** | Clean separation: router → service → repository → model. Zero leakage. | One minor abstraction gap | Business logic creeping into router or model | SQL in handlers; no repository layer | Circular imports; monolith file >500 lines |
| **Error Handling** | Every exception path typed, logged, re-raised or mapped to HTTP status | One missing edge-case handler | Bare `except:` or generic 500 for domain errors | Empty `catch` blocks | Silent failures; swallowed exceptions |
| **Testing** | 100% public API coverage; hypothesis property tests; fixtures typed | >80% coverage; no skipped tests | Some untested branches; one stale skip | <50% coverage; mocks test internals | No tests for new public functions |
| **Performance** | No N+1 queries; `selectinload` used correctly; async IO throughout | One minor query inefficiency | Synchronous DB call in async path | Unbounded loops; missing pagination | Blocking the event loop intentionally |
| **Security** | No secrets in code; SQLAlchemy param binding; input validated by Pydantic | One minor hardcoded default | `eval()` / `exec()` usage | SQL injection risk | Secrets committed; raw `text()` with f-strings |
| **Module Boundaries** | One writable module per change; manifest sync; cross-module tests pass | Minor manifest desync | Contract change without consumer update | Two modules edited without reading both | Launcher change without doctor coverage |
| **Documentation** | Every public function has Google-style docstring; ADRs referenced | One missing docstring | Docstrings present but inconsistent | No docstrings on public APIs | Outdated docs contradicting code |

### Audit Health Score

| Score Range | Rating | Action |
|-------------|--------|--------|
| 28–32 | Excellent | Approve with optional polish notes |
| 22–27 | Good | Approve with minor fix list |
| 16–21 | Acceptable | Conditional approval; fix P1s before merge |
| 8–15 | Poor | Reject; major refactor required |
| 0–7 | Critical | Halt; rewrite or escalate to senior review |

---

## Design System Checks (MANDATORY)

For any Python code that emits telemetry, status, or UI-facing data:

- Status signals MUST use the suite-wide semantic palette:
  - `healthy` → `#22C55E`
  - `error` → `#EF4444`
  - `degraded` / `warning` → `#F59E0B`
  - `running` → `#38BDF8`
  - `live` / `recording` → `#E11D48`
- Do NOT invent new status colour names or hex values.
- Launcher diagnostics MUST output structured JSON when `--json` is passed.

---

## Workflow Execution

Whenever you generate or review Python code, you must:

1. **Verify module context** — read the owning module's `AGENTS.md` and
   `pyproject.toml` before editing.
2. **Run the owning module's checks and autofixes** — first run `ruff check --fix .` and `ruff format .`, then run `mypy .` and
   `pytest` from the module directory.
3. **Cross-module gate** — if the change touches a contract, manifest, or
   public route, run:
   ```bash
   python3 -m pytest tests/integration/test_cross_module.py
   python3 -m pytest tests/integration/test_teensy_e2e.py
   ```
4. **Launcher gate** — if the change is under `nmtk/` or affects launcher
   behaviour, run:
   ```bash
   python3 scripts/launcher_control_service.py --doctor --json
   bash scripts/run_launcher_guardrails.sh
   ```
   Treat `fatalCount > 0` as a blocker.
5. **Optional-runtime gate** — verify that missing MuJoCo, BrainFlow, PYNQ,
   Akida, Lava, or SpiNNaker dependencies degrade gracefully; never crash
   the base service.
6. **ADR gate** — if the change introduces a new architectural decision, write
   a new ADR in `docs/ADR-claude/` or `docs/ADR-Codex/` (append-only; never
   rewrite existing ADRs).

---

## Report Format

When emitting an audit report, structure it exactly as follows:

```markdown
# Python Audit Report — {{module_name}} / {{file_path}}

## Audit Health Score: {{score}}/32 ({{rating}})

| Dimension | Score | Notes |
|-----------|-------|-------|
| Type Safety | {{0–4}} | ... |
| Architecture | {{0–4}} | ... |
| Error Handling | {{0–4}} | ... |
| Testing | {{0–4}} | ... |
| Performance | {{0–4}} | ... |
| Security | {{0–4}} | ... |
| Module Boundaries | {{0–4}} | ... |
| Documentation | {{0–4}} | ... |

## 🔴 Blocking Issues (P0)
- [ ] ...

## 🟡 Major Issues (P1)
- [ ] ...

## 💡 Suggestions (P2)
- [ ] ...

## Verification Commands Run
- `ruff check {{path}}` → {{exit_code}}
- `mypy {{path}}` → {{exit_code}}
- `pytest {{path}}` → {{summary}}
```

---

## Rules

- **Never approve code with a P0 issue unresolved.**
- **Never skip the owning module's `ruff` / `mypy` / `pytest` checks.**
- **Never change a contract in one module without checking the consumer.**
- **Never let launcher doctor `fatalCount > 0` pass unreported.**
- **Never treat optional hardware dependencies as fatal unless the manifest says so.**

## Symlink Note

This file is canonical. On Windows, if symlinks are unavailable, copy this file
from `.agents/skills/nmtk-python-review/SKILL.md` to the target platform paths.
