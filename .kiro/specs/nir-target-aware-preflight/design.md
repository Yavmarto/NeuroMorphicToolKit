# Design Document: NIR Target-Aware Preflight

## Overview

This feature adds a **preflight compatibility layer** to NeuroCNL Studio so
users see NIR graph compatibility status *before* clicking Run — replacing the
current experience where a HTTP 422 from `POST /api/simulators/run` is the
first signal that a graph is incompatible with the selected simulator backend.

The change has two halves that mirror each other:

- **Backend** — two new FastAPI endpoints that reuse the existing
  `classify_nir_graph` pipeline without dispatching to any simulator.
- **Frontend** — a new Riverpod `StateNotifierProvider` that manages preflight
  state, wired into `SimulatorPanel`, `PipelineBar`, and the spec-change cycle.

The Teensy `_scheduleDeployValidation` pattern (key-based debounce +
`addPostFrameCallback`) is the existing model for "auto-validate on target
selection"; this feature generalises it to simulator targets.

**Research summary**

- `classify_nir_graph` in `neurocnl/runtime/nir_support.py` already exposes
  the full `SupportClassification` dataclass (level, supported_nodes,
  approximate_nodes, unsupported_nodes, diagnostics).  No new Python logic is
  needed — the endpoints are thin wrappers.
- NIR HDF5 loading uses `nir.read(handle.name)` via a `NamedTemporaryFile`,
  as established in `neurocnl/neurosim/app/routers/generation.py`.  The new
  NIR preflight endpoint adopts the same pattern.
- The `_BACKEND_NIR_SUPPORT` table is the same for `lava_sim` and
  `snntorch_sim`; `classify_nir_graph` raises `ValueError` for unknown
  backends, which maps cleanly to HTTP 422.
- The existing `ApiClient` in `api_client.dart` uses a private `_post`
  helper for JSON bodies; multipart is already used in `nir_import_provider.dart`.
- `SimulatorPanel` already accepts `initialBackend` to lock the backend in the
  compact deploy-pane layout; the new `_PreflightResultWidget` slots in above
  `_CompactToolbar`.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Studio frontend (Flutter / Riverpod)                           │
│                                                                 │
│  spec_provider   →  pipeline_provider  ──────────────────┐     │
│       │                    │                              │     │
│       │ (spec change)       │ (validate success)          │     │
│       ▼                    ▼                              ▼     │
│  simulator_preflight_provider  ←  studio_screen._selectDeployTarget │
│       │ (state: idle/running/success/error)               │     │
│       │                                                   │     │
│  ┌────▼──────────────┐   ┌───────────────────────────┐   │     │
│  │_PreflightResult   │   │PipelineBar (deploy step)  │   │     │
│  │Widget             │   │reads simulatorPreflight   │   │     │
│  │(simulator_panel)  │   │Provider                   │   │     │
│  └────────────────── ┘   └───────────────────────────┘   │     │
│       │                                                   │     │
│  Run Button gating (disabled when level=unsupported)      │     │
└─────────────────────────────────────────────────────────────────┘
         │ POST /api/simulators/preflight          │
         │ POST /api/simulators/preflight-nir      │
         ▼                                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Backend (FastAPI)  neurocnl/backend/app/routers/simulators.py  │
│                                                                 │
│  preflight()        preflight_nir()                            │
│       │                    │                                    │
│  compile_to_nir(spec)   nir.read(tmpfile)                      │
│       │                    │                                    │
│       └──────┬─────────────┘                                    │
│              ▼                                                  │
│    classify_nir_graph(graph, backend_name)                      │
│    → SupportClassification                                      │
│              │                                                  │
│       HTTP 200 PreflightResult JSON                             │
└─────────────────────────────────────────────────────────────────┘
```

### Key design decisions

1. **No new Python logic** — both endpoints are coordinators. All classification
   intelligence lives in `classify_nir_graph` which already exists and is
   tested.

2. **Provider isolation** — `simulatorPreflightProvider` is separate from
   `simulatorRunProvider`. Preflight state does not affect the run lifecycle
   and vice versa.

3. **Key-based debounce** — identical to `_lastDeployValidationKeys` used for
   Teensy. The key is `'$backendName:${spec.hashCode}'` (CNL path) or
   `'$backendName:${nirBytesHash}'` (NIR path). A second call with the same
   key while a request is in-flight is silently dropped.

4. **Override mode is ephemeral** — it is scoped to the current preflight
   result. Any spec change, re-preflight, or provider invalidation resets it.

5. **Pipeline bar reuse** — `PipelineBar.build()` reads `simulatorPreflightProvider`
   only when a simulator target is active; otherwise it falls back to the
   existing `_deployStatusFor` logic unchanged.

---

## Components and Interfaces

### Backend components

| Component | File | Role |
|-----------|------|------|
| `PreflightRequest` schema | `backend/app/schemas/simulators.py` | Pydantic model for `/preflight` request body |
| `PreflightResult` schema | `backend/app/schemas/simulators.py` | Pydantic model for both preflight responses |
| `preflight()` endpoint | `backend/app/routers/simulators.py` | CNL → compile → classify → return |
| `preflight_nir()` endpoint | `backend/app/routers/simulators.py` | HDF5 bytes → load → classify → return |

### Frontend components

| Component | File | Role |
|-----------|------|------|
| `SimulatorPreflightState` | `providers/simulator_preflight_provider.dart` | Immutable state for one preflight lifecycle |
| `SimulatorPreflightNotifier` | `providers/simulator_preflight_provider.dart` | Calls API, manages lifecycle, debounce |
| `simulatorPreflightProvider` | `providers/simulator_preflight_provider.dart` | Riverpod provider |
| `PreflightResult` (Dart model) | `models/simulator_preflight.dart` | Deserializes `PreflightResult` JSON |
| `preflight()` in `ApiClient` | `services/api_client.dart` | JSON POST to `/api/simulators/preflight` |
| `preflightNir()` in `ApiClient` | `services/api_client.dart` | Multipart POST to `/api/simulators/preflight-nir` |
| `_PreflightResultWidget` | `widgets/simulator_panel.dart` | Renders classification result in Deploy panel |
| `PipelineBar` (modified) | `widgets/pipeline_bar.dart` | Reads preflight state for Deploy step |
| `pipeline_provider` (modified) | `providers/pipeline_provider.dart` | Triggers preflight after validate; invalidates on failure |
| `studio_screen` (modified) | `screens/studio_screen.dart` | Auto-triggers preflight on target selection / NIR import |

---

## Data Models

### Backend — Pydantic schemas (`backend/app/schemas/simulators.py`)

```python
class PreflightRequest(BaseModel):
    """Request body for POST /api/simulators/preflight."""
    spec: str = Field(..., description="CNL specification text to compile and classify.")
    backend_name: str = Field(
        ..., description="Simulator backend identifier: 'lava_sim' or 'snntorch_sim'."
    )


class PreflightResult(BaseModel):
    """Response body for both preflight endpoints.

    Shared by POST /api/simulators/preflight and POST /api/simulators/preflight-nir.
    """
    level: Literal["exact", "approximate", "unsupported"] = Field(
        ..., description="Overall NIR support classification for the backend."
    )
    supported_nodes: list[str] = Field(
        default_factory=list,
        description="NIR node type names that are exactly supported.",
    )
    approximate_nodes: list[str] = Field(
        default_factory=list,
        description="NIR node type names executed with approximate semantics.",
    )
    unsupported_nodes: list[str] = Field(
        default_factory=list,
        description="NIR node type names that cannot be executed.",
    )
    diagnostics: list[str] = Field(
        default_factory=list,
        description="Human-readable messages for approximate and unsupported nodes.",
    )
```

### Frontend — Dart state model (`models/simulator_preflight.dart`)

```dart
/// Mirrors the backend PreflightResult Pydantic schema.
class PreflightResult {
  final String level; // "exact" | "approximate" | "unsupported"
  final List<String> supportedNodes;
  final List<String> approximateNodes;
  final List<String> unsupportedNodes;
  final List<String> diagnostics;

  const PreflightResult({
    required this.level,
    required this.supportedNodes,
    required this.approximateNodes,
    required this.unsupportedNodes,
    required this.diagnostics,
  });

  factory PreflightResult.fromJson(Map<String, dynamic> json) =>
      PreflightResult(
        level: json['level'] as String,
        supportedNodes: List<String>.from(json['supported_nodes'] as List? ?? []),
        approximateNodes: List<String>.from(json['approximate_nodes'] as List? ?? []),
        unsupportedNodes: List<String>.from(json['unsupported_nodes'] as List? ?? []),
        diagnostics: List<String>.from(json['diagnostics'] as List? ?? []),
      );
}
```

### Frontend — Provider state model (`providers/simulator_preflight_provider.dart`)

```dart
enum SimulatorPreflightStatus { idle, running, success, error }

class SimulatorPreflightState {
  final SimulatorPreflightStatus status;
  final String? backendName;
  final String? level;               // "exact" | "approximate" | "unsupported"
  final List<String> supportedNodes;
  final List<String> approximateNodes;
  final List<String> unsupportedNodes;
  final List<String> diagnostics;
  final String? errorMessage;
  final bool overrideMode;

  const SimulatorPreflightState({
    this.status = SimulatorPreflightStatus.idle,
    this.backendName,
    this.level,
    this.supportedNodes = const [],
    this.approximateNodes = const [],
    this.unsupportedNodes = const [],
    this.diagnostics = const [],
    this.errorMessage,
    this.overrideMode = false,
  });

  SimulatorPreflightState copyWith({
    SimulatorPreflightStatus? status,
    String? backendName,
    String? level,
    List<String>? supportedNodes,
    List<String>? approximateNodes,
    List<String>? unsupportedNodes,
    List<String>? diagnostics,
    String? errorMessage,
    bool? overrideMode,
    bool clearLevel = false,
    bool clearError = false,
  }) =>
      SimulatorPreflightState(
        status: status ?? this.status,
        backendName: backendName ?? this.backendName,
        level: clearLevel ? null : (level ?? this.level),
        supportedNodes: supportedNodes ?? this.supportedNodes,
        approximateNodes: approximateNodes ?? this.approximateNodes,
        unsupportedNodes: unsupportedNodes ?? this.unsupportedNodes,
        diagnostics: diagnostics ?? this.diagnostics,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        overrideMode: overrideMode ?? this.overrideMode,
      );

  /// True when the Run button should be blocked by preflight.
  bool get runsBlocked =>
      (status == SimulatorPreflightStatus.running) ||
      (level == 'unsupported' && !overrideMode);
}
```

---

## Backend Endpoint Pseudocode

### `POST /api/simulators/preflight` (CNL input)

```python
@router.post(
    "/simulators/preflight",
    response_model=PreflightResult,
    summary="Classify a CNL spec against a simulator backend (no dispatch)",
    tags=["simulators"],
)
@limiter.limit("10/minute")
async def preflight(
    request: Request, response: Response, body: PreflightRequest
) -> PreflightResult:
    # ── 1. Validate backend name ──────────────────────────────────────────
    _KNOWN_BACKENDS = {"lava_sim", "snntorch_sim"}
    if body.backend_name not in _KNOWN_BACKENDS:
        raise HTTPException(
            status_code=422,
            detail=build_validation_failure_detail(
                f"Unknown simulator backend {body.backend_name!r}.",
                code="unknown_backend",
            ),
        )

    # ── 2. Compile CNL → NIR ──────────────────────────────────────────────
    try:
        graph = compile_to_nir(body.spec)
    except CompileError as exc:
        items = [
            {"code": d.code, "message": d.message, "line": d.line,
             "raw": d.raw, "hint": d.hint, "source": d.stage}
            for d in exc.diagnostics
        ]
        raise HTTPException(
            status_code=400,
            detail=build_backend_failure_detail(
                "compile_failed", items=items, source="compile"
            ),
        ) from exc

    # ── 3. Classify NIR support ───────────────────────────────────────────
    classification = classify_nir_graph(graph, body.backend_name)

    # ── 4. Return result — no simulator dispatch, no dependency check ─────
    return PreflightResult(
        level=classification.level,
        supported_nodes=classification.supported_nodes,
        approximate_nodes=classification.approximate_nodes,
        unsupported_nodes=classification.unsupported_nodes,
        diagnostics=classification.diagnostics,
    )
```

### `POST /api/simulators/preflight-nir` (raw NIR HDF5 input)

```python
@router.post(
    "/simulators/preflight-nir",
    response_model=PreflightResult,
    summary="Classify a raw NIR graph against a simulator backend (no dispatch)",
    tags=["simulators"],
)
@limiter.limit("10/minute")
async def preflight_nir(
    request: Request,
    response: Response,
    file: Annotated[UploadFile, File()],
    backend_name: Annotated[str, Form()],
) -> PreflightResult:
    # ── 1. Validate backend name ──────────────────────────────────────────
    _KNOWN_BACKENDS = {"lava_sim", "snntorch_sim"}
    if backend_name not in _KNOWN_BACKENDS:
        raise HTTPException(
            status_code=422,
            detail=build_validation_failure_detail(
                f"Unknown simulator backend {backend_name!r}.",
                code="unknown_backend",
            ),
        )

    # ── 2. Load NIR graph from HDF5 bytes ────────────────────────────────
    # Uses the same NamedTemporaryFile pattern as neurosim generation.py
    # because nir.read() may seek the file; BytesIO is insufficient.
    contents = await file.read()
    try:
        with tempfile.NamedTemporaryFile(suffix=".nir", delete=False) as tmp:
            tmp.write(contents)
            tmp_path = Path(tmp.name)
        graph = nir.read(str(tmp_path))
    except Exception as exc:
        raise HTTPException(
            status_code=422,
            detail=build_validation_failure_detail(
                f"Failed to parse NIR HDF5 file: {exc}",
                code="nir_parse_error",
            ),
        ) from exc
    finally:
        Path(tmp_path).unlink(missing_ok=True)

    # ── 3. Classify NIR support ───────────────────────────────────────────
    classification = classify_nir_graph(graph, backend_name)

    # ── 4. Return result — no simulator dispatch ──────────────────────────
    return PreflightResult(
        level=classification.level,
        supported_nodes=classification.supported_nodes,
        approximate_nodes=classification.approximate_nodes,
        unsupported_nodes=classification.unsupported_nodes,
        diagnostics=classification.diagnostics,
    )
```

---

## Frontend Provider Design

### `SimulatorPreflightNotifier` pseudocode

```dart
class SimulatorPreflightNotifier
    extends StateNotifier<SimulatorPreflightState> {

  SimulatorPreflightNotifier(this._ref)
      : super(const SimulatorPreflightState());

  final Ref _ref;
  String? _currentKey; // debounce key

  /// CNL-based preflight: POST /api/simulators/preflight
  Future<void> runPreflight(String spec, String backendName) async {
    final key = '$backendName:${spec.hashCode}';
    if (_currentKey == key &&
        state.status == SimulatorPreflightStatus.running) {
      return; // in-flight duplicate — skip
    }
    _currentKey = key;
    state = SimulatorPreflightState(
      status: SimulatorPreflightStatus.running,
      backendName: backendName,
    );
    try {
      final result = await _ref.read(apiClientProvider).preflight(spec, backendName);
      if (!mounted || _currentKey != key) return; // superseded
      state = SimulatorPreflightState(
        status: SimulatorPreflightStatus.success,
        backendName: backendName,
        level: result.level,
        supportedNodes: result.supportedNodes,
        approximateNodes: result.approximateNodes,
        unsupportedNodes: result.unsupportedNodes,
        diagnostics: result.diagnostics,
      );
    } on ApiException catch (e) {
      if (!mounted || _currentKey != key) return;
      state = SimulatorPreflightState(
        status: SimulatorPreflightStatus.error,
        backendName: backendName,
        errorMessage: _extractErrorMessage(e),
      );
    }
  }

  /// NIR-bytes-based preflight: POST /api/simulators/preflight-nir
  Future<void> runPreflightNir(
    Uint8List nirBytes,
    String backendName,
  ) async {
    final key = '$backendName:${nirBytes.hashCode}';
    if (_currentKey == key &&
        state.status == SimulatorPreflightStatus.running) {
      return;
    }
    _currentKey = key;
    state = SimulatorPreflightState(
      status: SimulatorPreflightStatus.running,
      backendName: backendName,
    );
    try {
      final result = await _ref
          .read(apiClientProvider)
          .preflightNir(nirBytes, backendName);
      if (!mounted || _currentKey != key) return;
      state = SimulatorPreflightState(
        status: SimulatorPreflightStatus.success,
        backendName: backendName,
        level: result.level,
        supportedNodes: result.supportedNodes,
        approximateNodes: result.approximateNodes,
        unsupportedNodes: result.unsupportedNodes,
        diagnostics: result.diagnostics,
      );
    } on ApiException catch (e) {
      if (!mounted || _currentKey != key) return;
      state = SimulatorPreflightState(
        status: SimulatorPreflightStatus.error,
        backendName: backendName,
        errorMessage: _extractErrorMessage(e),
      );
    }
  }

  /// Toggle override mode (re-enables Run button for unsupported graphs).
  void setOverrideMode(bool value) {
    state = state.copyWith(overrideMode: value);
  }

  /// Reset to idle — called on spec change, validate failure, or target switch.
  void invalidate() {
    _currentKey = null;
    state = const SimulatorPreflightState();
  }

  String _extractErrorMessage(ApiException e) {
    // Try to parse structured detail from the JSON body; fall back to body text.
    try {
      final decoded = jsonDecode(e.body) as Map<String, dynamic>;
      final detail = decoded['detail'];
      if (detail is String) return detail;
      if (detail is Map && detail['message'] is String) {
        return detail['message'] as String;
      }
    } catch (_) {}
    return 'Preflight failed (HTTP ${e.statusCode})';
  }
}

final simulatorPreflightProvider =
    StateNotifierProvider<SimulatorPreflightNotifier, SimulatorPreflightState>(
  (ref) => SimulatorPreflightNotifier(ref),
);
```

### `ApiClient` additions

```dart
// In ApiClient:

static const _simulatorsBase = '/simulators';

Future<PreflightResult> preflight(
  String spec,
  String backendName,
) async {
  final response = await _post(
    '$_simulatorsBase/preflight',
    {'spec': spec, 'backend_name': backendName},
  );
  return PreflightResult.fromJson(response);
}

Future<PreflightResult> preflightNir(
  Uint8List nirBytes,
  String backendName,
) async {
  final uri = Uri.parse('$baseUrl$_simulatorsBase/preflight-nir');
  final request = http.MultipartRequest('POST', uri);
  if (apiKey.isNotEmpty) {
    request.headers['X-API-Key'] = apiKey;
  }
  request.files.add(
    http.MultipartFile.fromBytes('file', nirBytes, filename: 'graph.nir'),
  );
  request.fields['backend_name'] = backendName;
  final streamed = await _http.send(request);
  final body = await streamed.stream.bytesToString();
  if (streamed.statusCode != 200) {
    throw ApiException(streamed.statusCode, body);
  }
  return PreflightResult.fromJson(
    jsonDecode(body) as Map<String, dynamic>,
  );
}
```

---

## Widget Structure: `_PreflightResultWidget`

Placed in `widgets/simulator_panel.dart`. In the compact deploy-pane layout
(`locked == true`), it is inserted in `_SimulatorPanelState.build()` above
`_CompactToolbar` so users see preflight status before interacting with the run
controls.

```
Column (simulator panel compact layout)
├── _PreflightResultWidget          ← NEW
├── _CompactToolbar (run bar)
│   └── FilledButton "Run Simulation"  ← disabled when runsBlocked
└── result area (tabs / placeholder)
```

### Widget states

```
status == idle
  → SizedBox.shrink() — region absent, not blank

status == running
  → Row(CircularProgressIndicator(strokeWidth: 2), Text('Checking compatibility…'))
     using AppTheme tokens, 12px compact padding

status == success, level == "exact"
  → _PreflightBadge(color: green, label: 'Fully supported')
  → _NodeList(title: 'Supported', nodes: supportedNodes)

status == success, level == "approximate"
  → _PreflightBadge(color: amber, label: 'Approximate')
  → _NodeList(title: 'Approximate', nodes: approximateNodes, caution: true)
  → _NodeList(title: 'Supported', nodes: supportedNodes)

status == success, level == "unsupported"
  → _PreflightBadge(color: red, label: 'Unsupported')
  → _NodeList(title: 'Unsupported', nodes: unsupportedNodes, showDiagnostics: true)
  → if supportedNodes.isNotEmpty: _NodeList(title: 'Supported', nodes: supportedNodes)
  → if approximateNodes.isNotEmpty: _NodeList(title: 'Approximate', nodes: approximateNodes)
  → _OverrideToggle(
       active: preflight.overrideMode,
       onChanged: (v) => ref.read(simulatorPreflightProvider.notifier).setOverrideMode(v),
    )

status == error
  → Row(Icon(error_outline, red), Text(errorMessage, style: errorTextStyle))
    (Run button area remains visible and at default enabled/disabled state)
```

### Run button gating (in `_CompactToolbar`)

```dart
// Derive the effective enabled state:
final preflightState = ref.watch(simulatorPreflightProvider);
final bool preflightBlocking = preflightState.runsBlocked;
// runsBlocked = status==running || (level=="unsupported" && !overrideMode)

FilledButton.icon(
  onPressed: (isLoading || preflightBlocking) ? null : onRun,
  label: Text(isLoading ? 'Running…' : 'Run Simulation'),
  ...
)

// Tooltip wrapper:
Tooltip(
  message: switch (true) {
    _ when preflightState.status == SimulatorPreflightStatus.running =>
        'Preflight in progress — please wait.',
    _ when preflightState.level == 'unsupported' && !preflightState.overrideMode =>
        'Unsupported node types detected. See preflight results above.',
    _ when preflightState.level == 'approximate' =>
        'Approximate nodes: ${preflightState.approximateNodes.join(", ")}',
    _ => '',
  },
  child: FilledButton.icon(...),
)
```

---

## Pipeline Bar Integration

`pipeline_bar.dart` is modified to read `simulatorPreflightProvider` when a
simulator target is active. The existing `_deployStatusFor` logic is preserved
as the fallback for all non-simulator targets.

```dart
// In PipelineBar.build():
final preflightState = ref.watch(simulatorPreflightProvider);
final selectedTarget = ref.watch(
  workspaceProvider.select((w) => w.selectedDeployTarget),
);
final isSimulatorTarget =
    selectedTarget == 'lava_sim' || selectedTarget == 'snntorch_sim';

NmtkStepData(
  id: 'deploy',
  label: l10n.deploy,
  status: isSimulatorTarget
      ? _preflightDeployStatus(preflightState)
      : _mapStatus(_deployStatusFor(pipeline)),
  detail: isSimulatorTarget
      ? _preflightDeployDetail(preflightState)
      : _deployDetailFor(pipeline),
),

// Mapping helpers:
NmtkStepStatus _preflightDeployStatus(SimulatorPreflightState s) =>
    switch (s.status) {
      SimulatorPreflightStatus.running => NmtkStepStatus.running,
      SimulatorPreflightStatus.success => switch (s.level) {
          'unsupported' => NmtkStepStatus.error,
          _ => NmtkStepStatus.success,   // exact or approximate
        },
      SimulatorPreflightStatus.error => NmtkStepStatus.error,
      SimulatorPreflightStatus.idle => _mapStatus(_deployStatusFor(pipeline)),
    };

String? _preflightDeployDetail(SimulatorPreflightState s) =>
    switch (s.status) {
      SimulatorPreflightStatus.running => 'Preflight…',
      SimulatorPreflightStatus.success => switch (s.level) {
          'exact' => 'Preflight OK',
          'approximate' => 'Approximate',
          'unsupported' => 'Unsupported nodes',
          _ => null,
        },
      SimulatorPreflightStatus.error => 'Preflight error',
      SimulatorPreflightStatus.idle => _deployDetailFor(pipeline),
    };
```

---

## Studio Screen Integration

### Target selection (`_selectDeployTarget`)

```dart
void _selectDeployTarget(String targetId) {
  ref.read(workspaceProvider.notifier).setSelectedDeployTarget(targetId);
  // NEW: trigger preflight for simulator targets, invalidate for others.
  _scheduleSimulatorPreflight(targetId);
}

static const _simulatorTargets = {'lava_sim', 'snntorch_sim'};

void _scheduleSimulatorPreflight(String targetId) {
  if (!_simulatorTargets.contains(targetId)) {
    // Hardware target — invalidate stale preflight state.
    ref.read(simulatorPreflightProvider.notifier).invalidate();
    return;
  }
  final spec = ref.read(specTextProvider);
  final nirState = ref.read(nirImportProvider);
  final isNirFile = nirState.source == NirSource.file &&
      nirState.status == NirImportStatus.loaded;

  // Key-based debounce (mirrors _lastDeployValidationKeys for Teensy).
  final key = isNirFile
      ? '$targetId:nir:${nirState.result.hashCode}'
      : '$targetId:cnl:${spec.hashCode}';
  if (_lastDeployValidationKeys[targetId] == key) return;
  _lastDeployValidationKeys[targetId] = key;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    if (isNirFile) {
      // Extract the raw bytes from the canonical NIR artifact cache.
      final nirBytes = _resolveNirBytes();
      if (nirBytes != null) {
        ref.read(simulatorPreflightProvider.notifier)
            .runPreflightNir(nirBytes, targetId);
        return;
      }
    }
    ref.read(simulatorPreflightProvider.notifier)
        .runPreflight(spec, targetId);
  });
}
```

### Deploy panel open (`_buildPanelContent`)

```dart
Widget _buildPanelContent(String panelId) {
  final selectedTarget = ref.watch(
    workspaceProvider.select((w) => w.selectedDeployTarget),
  );
  if (panelId == 'deploy') {
    _syncSelectedHardwareProvider(selectedTarget);
    _scheduleDeployValidation(selectedTarget);   // ← unchanged (Teensy)
    _scheduleSimulatorPreflight(selectedTarget); // ← NEW
  }
  // ...rest unchanged
}
```

### NIR import hook (`nir_importer_tab.dart`)

After `NirImportState` transitions to `loaded` with `source == NirSource.file`,
the write-back callback in `_NirImporterTabState` already fires via
`addPostFrameCallback`. We extend it to also schedule a preflight:

```dart
// At the end of _applyWriteBack(), after consuming the NIR write-back:
final selectedTarget =
    ref.read(workspaceProvider.select((w) => w.selectedDeployTarget));
if (_simulatorTargets.contains(selectedTarget)) {
  final nirBytes = state.result?.rawBytes; // raw bytes stored in NirInspectResult
  if (nirBytes != null) {
    ref.read(simulatorPreflightProvider.notifier)
        .runPreflightNir(nirBytes, selectedTarget);
  }
}
```

> **Note**: `NirImportNotifier.inspectFile` already stores `bytes` during the
> upload. The `NirInspectResult` model needs a `rawBytes` field (or the bytes
> are kept in `NirImportState`) so that the write-back callback can forward
> them to the preflight provider without re-reading the file.

### `pipeline_provider.dart` — target-aware validate and preflight trigger

```dart
Future<void> runParseAndValidate(
  String spec, {
  String? backendOverride,  // NEW parameter, used by studio_screen
}) async {
  if (spec.trim().isEmpty) {
    state = const PipelineState();
    // Invalidate stale preflight when spec is cleared.
    _ref.read(simulatorPreflightProvider.notifier).invalidate();
    return;
  }

  final selectedTarget = _ref.read(workspaceProvider).selectedDeployTarget;
  final bool isSimulator = selectedTarget == 'lava_sim' ||
      selectedTarget == 'snntorch_sim';
  final String backend = isSimulator ? selectedTarget : 'nir';

  // ... existing parse + validate logic with backend = backend ...

  // After successful validate:
  if (isSimulator && state.validateStatus == StepStatus.success) {
    _ref.read(simulatorPreflightProvider.notifier)
        .runPreflight(spec, selectedTarget);
  }
  // After failed validate:
  if (state.validateStatus == StepStatus.error) {
    _ref.read(simulatorPreflightProvider.notifier).invalidate();
  }
}
```

Calling sites in `studio_screen.dart` that currently call
`runParseAndValidate(content)` require no changes — the provider reads
`selectedDeployTarget` internally.

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all
valid executions of a system — essentially, a formal statement about what the
system should do. Properties serve as the bridge between human-readable
specifications and machine-verifiable correctness guarantees.*

#### Property Reflection — Pre-consolidation

Before writing final properties, redundancy was evaluated across the prework
criteria:

- Requirements 1.2, 1.3, 2.2, and 2.3 all test the same pipeline (graph →
  classify → structured response). They consolidate into **two properties**
  (one per endpoint) that verify both the classification result and the response
  shape simultaneously.
- Requirements 1.4 and 2.4 are analogous error-input properties across the two
  endpoints; kept as separate properties because the input spaces differ (CNL
  text vs. HDF5 bytes).
- Requirements 1.5 and 2.5 both test unknown-backend rejection; consolidated
  into a single property with a shared generator.
- Requirements 3.2 and 3.3 describe the same state machine lifecycle (running
  → success/error) for two API methods; consolidated into one property.
- Requirements 3.4, 4.5, and 8.6 all express the same debounce/idempotence
  invariant; consolidated into one property.
- Requirements 3.5, 8.6 (override reset), and 10.3 all express "invalidate on
  spec change"; consolidated into one property.
- Requirements 9.1 through 9.6 and 11.4 describe the same pipeline-bar mapping
  function; consolidated into one property.
- Requirements 10.1 and 10.2 are one property: the pipeline provider reacts
  correctly to validate outcome for simulator targets.
- Requirements 4.4, 5.2, 5.3, and 11.1 (no preflight for hardware/no-target)
  are consolidated into one negative property.
- Requirements 6.1 and 6.2 are two sides of one property (backend selection
  for validate).

---

### Property 1: Preflight endpoint response completeness (CNL path)

*For any* valid CNL spec and any known backend name (`lava_sim` or
`snntorch_sim`), calling `POST /api/simulators/preflight` SHALL return HTTP 200
with a response body that contains `level` (one of "exact", "approximate",
"unsupported"), and `supported_nodes`, `approximate_nodes`, `unsupported_nodes`,
`diagnostics` (all lists of strings), such that the level is consistent with the
node lists (non-empty `unsupported_nodes` → level is "unsupported";
non-empty `approximate_nodes` and no unsupported → level is "approximate").

**Validates: Requirements 1.2, 1.3**

---

### Property 2: Preflight endpoint response completeness (NIR path)

*For any* valid NIR graph serialised to HDF5 bytes and any known backend name,
calling `POST /api/simulators/preflight-nir` SHALL return HTTP 200 with the
same response shape and level consistency as Property 1, and the
classification SHALL match the result of calling `classify_nir_graph(graph,
backend_name)` directly on the same graph.

**Validates: Requirements 2.2, 2.3**

---

### Property 3: Compile error maps to HTTP 400

*For any* string that cannot be parsed as a valid CNL spec, `POST /api/simulators/preflight`
SHALL return HTTP 400 with a `compile_failed` error code and a non-empty `items`
list containing at least one diagnostic with `source == "compile"`.

**Validates: Requirements 1.4**

---

### Property 4: Invalid HDF5 maps to HTTP 422 with nir_parse_error

*For any* byte sequence that is not a valid NIR HDF5 file,
`POST /api/simulators/preflight-nir` SHALL return HTTP 422 with error code
`nir_parse_error` and a non-empty human-readable message.

**Validates: Requirements 2.4**

---

### Property 5: Unknown backend rejected at both endpoints

*For any* string that is not in `{"lava_sim", "snntorch_sim"}`, both
`POST /api/simulators/preflight` and `POST /api/simulators/preflight-nir`
SHALL return HTTP 422 with error code `unknown_backend`.

**Validates: Requirements 1.5, 2.5**

---

### Property 6: Provider state lifecycle (running → success/error)

*For any* `(spec, backendName)` or `(nirBytes, backendName)` pair, when
`runPreflight` or `runPreflightNir` is called on the `SimulatorPreflightNotifier`,
the state SHALL transition idle/error/success → running immediately, and then
transition to success (with a populated `level` and consistent node lists)
when the mock API returns a valid `PreflightResult`, or transition to error
(with a non-null `errorMessage`) when the mock API raises an `ApiException`.

**Validates: Requirements 3.1, 3.2, 3.3**

---

### Property 7: Debounce — in-flight duplicates are dropped

*For any* key (same `backendName` + `specHash`), if `runPreflight` is called
twice while the first request is in-flight (using a delayed mock), the notifier
SHALL issue exactly one HTTP POST, not two. The second call is a no-op.

**Validates: Requirements 3.4, 4.5**

---

### Property 8: Invalidation resets all state (including override mode)

*For any* non-idle preflight state (including `overrideMode == true`), calling
`invalidate()` SHALL transition the state to `SimulatorPreflightStatus.idle`
with `level == null`, `overrideMode == false`, empty node lists, and
`errorMessage == null`.

**Validates: Requirements 3.5, 8.6, 10.3**

---

### Property 9: Pipeline bar deploy step maps correctly from preflight state

*For any* `SimulatorPreflightState` and any simulator target selection, the
`PipelineBar`'s deploy step status SHALL be:
- `running` when `status == running`
- `success` when `status == success && level != "unsupported"`
- `error` when `status == success && level == "unsupported"` or `status == error`
- the fallback `_deployStatusFor(pipeline)` when `status == idle`

AND when a hardware target is selected (or no target), the deploy step SHALL
always use `_deployStatusFor(pipeline)` regardless of any preflight state.

**Validates: Requirements 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 11.4**

---

### Property 10: Run button blocked by unsupported or in-flight preflight

*For any* `SimulatorPreflightState` where `runsBlocked` is true (i.e., status
is `running`, or `level == "unsupported" && !overrideMode`), the Run button's
`onPressed` callback SHALL be null (disabled). Conversely, *for any* state where
`runsBlocked` is false, the Run button's enabled state SHALL be determined
solely by the existing availability and spec-empty checks.

**Validates: Requirements 8.1, 8.2, 8.4**

---

### Property 11: Override activation enables run for unsupported graphs

*For any* `PreflightResult` where `level == "unsupported"`, setting
`overrideMode = true` via `setOverrideMode(true)` SHALL result in
`runsBlocked == false` (Run button re-enabled) while all other state fields
remain unchanged.

**Validates: Requirements 8.5**

---

### Property 12: Pipeline provider uses simulator backend for validate

*For any* active deploy target in `{"lava_sim", "snntorch_sim"}`, calling
`runParseAndValidate` SHALL pass that target's identifier as the `backend`
parameter to `api.validate()`. *For any* non-simulator target (including
null/empty), the backend parameter SHALL be `"nir"`.

**Validates: Requirements 6.1, 6.2**

---

### Property 13: Preflight triggered after successful validate for simulator target

*For any* successful validate result when a simulator target is selected, the
`PipelineNotifier` SHALL call `simulatorPreflightProvider.notifier.runPreflight`
with the validated spec and the selected backend name. When validate fails, it
SHALL call `invalidate()` instead.

**Validates: Requirements 10.1, 10.2**

---

### Property 14: Hardware targets never trigger simulator preflight

*For any* hardware target selection (teensy, pynq, akida, lava) — whether via
`_selectDeployTarget`, NIR file import, or `runParseAndValidate` completion —
`simulatorPreflightProvider.notifier.runPreflight` and `.runPreflightNir` SHALL
never be called.

**Validates: Requirements 4.4, 5.2, 5.3, 11.1**

---

### Property 15: NIR import triggers runPreflightNir for active simulator target

*For any* `NirImportState` that transitions to `status == loaded` with
`source == NirSource.file`, if the currently selected deploy target is a
simulator target, the `SimulatorPreflightNotifier.runPreflightNir` SHALL be
called with the loaded NIR bytes and the selected backend name. If no simulator
target is selected, it SHALL NOT be called.

**Validates: Requirements 5.1, 5.2**

---

## Error Handling

### Backend

| Situation | HTTP status | Error code | Notes |
|-----------|------------|------------|-------|
| `backend_name` not in `{"lava_sim", "snntorch_sim"}` | 422 | `unknown_backend` | Both endpoints |
| CNL fails to compile (`CompileError`) | 400 | `compile_failed` | CNL endpoint only; same format as `/run` |
| HDF5 bytes cannot be parsed by `nir.read()` | 422 | `nir_parse_error` | NIR endpoint only; human-readable message |
| Temporary file cleanup fails | Silently swallowed | — | `finally: unlink(missing_ok=True)` |
| Rate limit exceeded | 429 | (slowapi default) | Same as `/run` |

The endpoints intentionally never return 503 — they do not check whether
`lava` or `snntorch` are installed. That check lives in `/run` only.

### Frontend provider

| Situation | State transition | Notes |
|-----------|-----------------|-------|
| `ApiException` (any status) | `status = error`, `errorMessage` set | `_extractErrorMessage` parses structured body |
| Call with same key while in-flight | No state change | Debounce guard |
| `mounted == false` on response return | No state change | Stale response guard |
| Spec cleared (empty string) | `invalidate()` called by `PipelineNotifier` | Clears all fields |
| Target switched to hardware | `invalidate()` called by `_selectDeployTarget` | |
| Validate failure | `invalidate()` called by `PipelineNotifier` | |

### UI error surfaces

- `_PreflightResultWidget` in the deploy panel renders the `errorMessage`
  inline with a red icon. The Run button area remains visible so the user can
  still attempt to run (perhaps the spec has since been corrected).
- `nir_parse_error` from the NIR preflight endpoint does not prevent the NIR
  import write-back from completing — the two flows are independent.

---

## Testing Strategy

### Property-based tests (pytest-hypothesis — Python backend)

Property-based tests run a minimum of 100 iterations each and are tagged:
`Feature: nir-target-aware-preflight, Property {N}: {property_text}`

**Library**: [Hypothesis](https://hypothesis.readthedocs.io/)

- **Property 1** — `test_preflight_cnl_response_completeness`
  Strategies: `st.from_regex(valid_cnl_pattern)` or a small CNL fixture corpus;
  `st.sampled_from(["lava_sim", "snntorch_sim"])`.
  Assert: HTTP 200, all fields present, level consistency invariant.

- **Property 2** — `test_preflight_nir_response_completeness`
  Strategies: Build random `nir.NIRGraph` objects in-process, serialise with
  `nir.write(graph, tmpfile)`, read bytes. Assert: HTTP 200, response matches
  `classify_nir_graph(graph, backend_name)`.

- **Property 3** — `test_preflight_cnl_compile_error`
  Strategies: `st.text()` filtered to strings that fail `compile_to_nir`.
  Assert: HTTP 400, `compile_failed` code.

- **Property 4** — `test_preflight_nir_parse_error`
  Strategies: `st.binary()` | random truncated HDF5. Assert: HTTP 422,
  `nir_parse_error` code.

- **Property 5** — `test_preflight_unknown_backend`
  Strategies: `st.text().filter(lambda s: s not in {"lava_sim", "snntorch_sim"})`.
  Assert: HTTP 422, `unknown_backend` code, for both endpoints.

### Property-based tests (Dart / flutter_test + fast_check-style, or Hypothesis via dart_hypothesis)

Given no mature PBT library in Flutter, these are implemented using the
[`glados`](https://pub.dev/packages/glados) package (Dart PBT library).

- **Property 6** — `test_preflight_provider_state_lifecycle`
  Arbitrary: `(spec, backendName)` pairs; mock `ApiClient` returning
  `PreflightResult` or throwing `ApiException`. Assert state transitions.

- **Property 7** — `test_preflight_provider_debounce`
  Arbitrary: `(spec, backendName)` pairs. Assert one HTTP call per key while
  in-flight.

- **Property 8** — `test_preflight_provider_invalidation`
  Arbitrary initial states (including overrideMode=true). Assert full reset.

- **Property 9** — `test_pipeline_bar_deploy_step_mapping`
  Arbitrary `SimulatorPreflightState` values. Assert status mapping function
  is correct for all inputs.

- **Property 10** — `test_run_button_gating`
  Arbitrary `SimulatorPreflightState`. Assert `runsBlocked` derivation.

- **Property 11** — `test_override_enables_run`
  Arbitrary unsupported PreflightResult. Assert overrideMode=true → runsBlocked=false.

- **Property 12** — `test_validate_backend_selection`
  Arbitrary `(spec, deployTarget)`. Assert correct backend passed to mock ApiClient.

- **Property 13** — `test_pipeline_preflight_trigger_on_validate`
  Arbitrary `(spec, simulatorTarget)`. Assert runPreflight called on success,
  invalidate called on failure.

- **Property 14** — `test_no_preflight_for_hardware_targets`
  Arbitrary hardware target IDs. Assert runPreflight never called.

- **Property 15** — `test_nir_import_triggers_preflight`
  Arbitrary `(nirBytes, simulatorTarget)`. Assert runPreflightNir called.

### Unit tests (specific examples)

- Endpoint exists and accepts correct schema (Requirement 1.1, 2.1)
- No 503 when lava / snntorch not installed (Requirements 1.6, 2.6)
- Override toggle appears in widget when level=unsupported (Requirement 8.5)
- Validation panel displays backend name when set (Requirement 6.4)
- Teensy `_scheduleDeployValidation` still fires (Requirement 11.2)
- `POST /api/simulators/run` returns same result as before (Requirement 11.3)

### Integration tests

- Rate limit header present on preflight endpoints (Requirements 1.7, 2.7)
- End-to-end: select simulator target, observe pipeline bar Deploy step change
  to running → success (requires running backend)

### Test configuration

Each property-based test MUST be configured with a minimum of 100 iterations
(Hypothesis `settings(max_examples=100)` / glados equivalent). Tags follow the
format: `Feature: nir-target-aware-preflight, Property N: <property_text>`.
