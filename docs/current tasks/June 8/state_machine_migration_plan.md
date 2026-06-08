# State Machine Architectural Migration Plan

This document outlines a thorough, phased implementation plan to adopt formal State Machine patterns across both the NMTK frontend (Flutter/Riverpod 3) and backend (FastAPI/Python 3.10).

## Open Questions

> [!WARNING]
> Do you have a specific module or feature (e.g., `neurocnl` simulation, or `Neurochip` hardware connection) that you would like to migrate first as a pilot/proof-of-concept? Or should I start with the most critical one I find?

## Proposed Changes

---

### Phase 1: Foundation & Data Modeling

**Objective:** Define the discrete states without modifying any application logic or UI.

#### Frontend (Flutter / Riverpod)
Identify complex state structs (e.g., connection statuses, complex dialogs, simulation lifecycles).
- **[NEW]** Create Freezed union types for these states in `lib/src/features/[feature]/domain/`.
  *(e.g., `const factory ConnectionState.connecting()`, `.connected()`, `.error()`)*

#### Backend (FastAPI / Python)
Identify status enums and optional-heavy models (e.g., `SimulationJobStatus`).
- **[NEW]** Create Pydantic discriminated unions using `Discriminator` for state-specific payloads.
  *(e.g., separate `SimulationRunning` and `SimulationError` classes that inherit from a base `SimulationState`)*

---

### Phase 2: State Controllers & Business Logic

**Objective:** Build the state machines that control transitions.

#### Frontend
- **[NEW/MODIFY]** Create new `@riverpod` Notifiers (or AsyncNotifiers) in the `presentation/` or `application/` layer that hold the Freezed union state.
- **[MODIFY]** Expose transition methods (Events) that enforce valid state changes (e.g., preventing a transition to `.connected()` if the state is `.disconnected()`).

#### Backend
- **[MODIFY]** Update background services and job managers to enforce state transitions.
- **[MODIFY]** Replace chained `if-elif` statements validating `job.status` with Python 3.10+ `match-case` blocks over the new Pydantic union types, ensuring exhaustive logic checks.

---

### Phase 3: Consumer Integration

**Objective:** Wire up the UI and API endpoints to the new deterministic states.

#### Frontend (UI Consumption)
- **[MODIFY]** Refactor ConsumerWidgets to use Dart 3 `switch` expressions on `ref.watch(provider)`.
- **[DELETE]** Remove defensive UI checks like `if (isLoading && !hasError)`. The compiler will now guarantee all states are handled via the `switch`.

#### Backend (API Endpoints)
- **[MODIFY]** Update FastAPI routers to return the new discriminated union schemas in OpenAPI endpoints.
- **[MODIFY]** Ensure endpoint input validation strictly rejects impossible state transitions requested by the client.

## Verification Plan

### Automated Tests
- Run backend unit tests (`pytest tests/`) to ensure Pydantic models serialize/deserialize discriminated unions correctly.
- Run frontend unit tests to ensure Riverpod Notifiers correctly reject invalid transition events.

### Manual Verification
- Deploy the pilot module locally.
- Force error states (e.g., disconnect a device mid-process, simulate network failure) to verify the UI correctly and exhaustively transitions to the error state without hanging in an impossible "loading + error" state.
