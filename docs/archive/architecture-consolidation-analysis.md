# Architecture Consolidation Analysis

## Recommendation

**Yes — you should move away from the current “seven backend + seven frontend” runtime architecture.**  
Given the current product direction, the best target is **one suite frontend and one primary suite backend**, while keeping the domain modules as **internal packages / bounded contexts**, not as separately launched apps.

I would **not** recommend keeping the current service split as the long-term default, and I would also **not** recommend collapsing everything into an undifferentiated monolith. The right move is a **modular monolith with optional workers**, not a microservice-style suite and not a giant bag of code.

## Why the current architecture made sense before

The current architecture was designed around three assumptions that are visible in the repo:

1. `README.md` and `nmtk/neuro_toolkit/SPEC.md` frame NMTK as a launcher/catalog for separately installable tools.
2. `nmtk/docs/ADR-claude/0004-webview-module-embedding.md` explicitly chooses WebView embedding because each module has its own frontend served by its own FastAPI backend.
3. `nmtk/neuro_toolkit/assets/modules.json` and `nmtk/docs/ADR-claude/0001-module-manifest-system.md` assume a manifest-driven fleet of separately started services with per-module ports, health checks, and lifecycle states.

That architecture is coherent **if** the main goal is:

- independent distribution
- optional installation
- future third-party module publishing
- strong standalone boundaries

But that is no longer your main goal.

## Why the current architecture is now a bad fit

The repo now shows a pattern where the modules are **separate at runtime** but **not truly separate as products**.

### 1. Startup and local-dev overhead is very high

`SETUP_GUIDE.md` documents separate backend startup commands per module, separate frontend commands per module, separate ports, and separate build steps for each frontend. The launcher then exists largely to hide that operational complexity by creating venvs, launching `uvicorn`, polling health, and embedding each module in a WebView.

That means the architecture is creating complexity and then building another layer to compensate for it.

### 2. The modules are interconnected, not independent

The earlier overlap analysis is already pointing in this direction: the suite behaves like one workflow split across many apps.

Examples from the repo:

- `docker-compose.yml` brings up multiple tightly related services on fixed ports.
- `Neurohub/neurohub/app/services/suite_client.py` actively calls other module APIs and tracks their health.
- `docs/api/README.md` documents the suite as a set of local services that are expected to be running together.
- `nmtk/AGENTS.md` says module UIs are embedded web frontends rather than truly separate user experiences.

This is not “seven independently valuable SaaS products.” It is much closer to **one product with seven domains**.

### 3. You are paying duplicate frontend and backend tax

For each module, the split architecture creates duplicate:

- API surface
- health endpoints
- startup scripts
- deployment wiring
- frontend build/release pipeline
- environment/config handling
- CI wiring
- cross-module contracts
- docs and status drift risk

The repo already shows the cost of this duplication:

- stale top-level architecture docs
- conflicting module identities, especially around Neurohub
- manifest drift risk called out in the launcher ADRs and AGENTS files
- per-module frontend build scripts such as `scripts/build_module.sh` and `scripts/build_all_frontends.sh`

### 4. The “standalone module” benefit is weaker than it looks

The strongest reason to tolerate this complexity would be real standalone value. But the repo increasingly suggests the opposite:

- the launcher is the primary entrypoint
- the modules share a design system (`nmtk_ui_core`)
- several modules depend on artifacts or semantics from others
- some domain splits are already blurred (`neurocnl` / `Neurosim`, `Neurosense` / `Neuro-Dream-Hand`, `nmtk` / `Neurohub`)

So today you have many of the costs of microservices without the full benefits of true product independence.

## Why a total flattening into one giant codebase is also the wrong move

You should consolidate the runtime architecture, but **keep the domain boundaries**.

There are still real reasons not to smash everything together carelessly:

1. Hardware and optional dependencies are very uneven across the modules.
2. Some areas have very different risk profiles: biosignal acquisition, hardware flashing, simulation, benchmarking, orchestration.
3. The current module boundaries are still useful as ownership boundaries, test boundaries, and conceptual boundaries.
4. You may still want future extractability, even if you do not want a public module marketplace right now.

So the goal should be:

- **merge runtime boundaries**
- **keep code boundaries**

## Best target architecture

### A. One frontend

Move toward a single Flutter app for the suite experience instead of multiple separately built module frontends embedded in WebViews.

That means:

- no more per-module web frontend as the default delivery mechanism
- no more launcher embedding localhost web apps for core workflows
- one navigation shell, one routing system, one state model, one release artifact
- domain-specific screens living as internal feature packages or folders

You already have `nmtk` and `nmtk_ui_core`; they are the natural base for this.

### B. One primary backend

Move toward one main Python backend for the suite’s core workflows and shared persistence.

That backend should own:

- project/session/workflow state
- shared auth/config if needed
- artifact registry metadata
- handoff orchestration
- internal access to domain services without HTTP hops by default

Domain areas such as CNL parsing, graph transforms, benchmarking logic, encoding, and deployment preparation should remain as **internal Python packages** called directly in-process wherever possible.

### C. Optional workers for the genuinely special cases

Keep separate processes only where they are justified by runtime reality, for example:

- hardware-facing drivers
- long-running benchmark jobs
- MuJoCo / simulation-heavy workloads
- failure-prone optional integrations

Those should be treated as **workers/adapters**, not full first-class product backends with their own full frontend + backend stack unless there is a strong reason.

### D. Internal module boundaries stay real

Keep the current product modules as bounded contexts:

- `neurocnl`
- `Neurosim`
- `Neurochip`
- `Neurobench`
- `Neurosense`
- `Neurohub`
- `Neuro-Dream-Hand`

But reinterpret them as:

- internal packages
- feature areas
- ownership domains
- test scopes

not necessarily as separately deployed apps.

## What this would improve

| Area | Current split architecture | Consolidated architecture |
|---|---|---|
| User experience | Launcher opens many embedded apps | One coherent product |
| Frontend work | Repeated app shells and build pipelines | One UI platform |
| Backend work | Repeated API/process/config surfaces | One main API surface |
| Integration | HTTP hops across localhost services | In-process calls where appropriate |
| Startup | Multiple services and health checks | Simpler default startup |
| Documentation | Easy for docs to drift by module | Easier to describe one product |
| Testing | Many end-to-end boundaries | More unit/integration coverage inside one system |
| Future extraction | Possible but expensive | Still possible if boundaries stay clean |

## What would get worse

| Risk | Why it matters |
|---|---|
| Larger blast radius | A bad backend change can affect more of the suite at once |
| Dependency conflict risk | Optional hardware stacks still need careful isolation |
| Bigger app complexity | One codebase can become tangled if boundaries are not enforced |
| Migration cost | This is a real architectural refactor, not a cosmetic cleanup |

These are real risks, but they are manageable if the target is a **modular monolith**, not a careless merge.

## Bottom-line advice

If your priorities are now:

- one coherent product
- less startup friction
- less operational overhead
- fewer duplicated frontends/backends
- stronger integrated workflows

then **the current architecture is the wrong default**.

My advice is:

1. **Do not keep the current “one backend + one frontend per module” architecture as the long-term plan.**
2. **Do not merge everything into a shapeless monolith either.**
3. **Consolidate into one suite frontend and one primary suite backend, while retaining module boundaries as internal packages and optional worker processes.**

That gives you the advantages you actually need now, while still leaving room to re-expose selected capabilities later if you decide to reintroduce a marketplace or plugin system in a different form.

## Recommended strategic decision

**Recommended decision:**  
Shift from **module-as-app** architecture to **module-as-domain** architecture.

In practice, that means:

- one product
- one main UI
- one main backend
- several internal domains
- optional isolated workers only where technically necessary

## Suggested migration order

1. **Stop investing in per-module frontend independence as a strategic goal.**
2. **Define the future suite backend boundaries**: core API, jobs/workers, hardware adapters.
3. **Unify the frontend into the launcher shell** instead of continuing the WebView-hosted-app model.
4. **Collapse cross-module localhost API calls into in-process package calls** where no real deployment boundary is needed.
5. **Keep only the runtime separations that are justified by hardware isolation, optional dependencies, or long-running jobs.**
6. **Reposition Neurohub and nmtk around the new architecture** so there is one control-plane truth and one registry/story.

## Final verdict

**Yes: overhaul the architecture.**  
Not toward “seven cleaner microservices,” but toward **one integrated application with strong internal domain boundaries**.

That is the architecture that best matches the product you appear to be building now.
