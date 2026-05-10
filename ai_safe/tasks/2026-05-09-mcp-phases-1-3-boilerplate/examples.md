# Examples And Acceptance Tests

Provide exact examples whenever possible.

## Input/Output Examples

### Example 1: authoring guide

Input:

```python
guide = get_cnl_authoring_guide(paths, intent="reflex arc", target_backend="nengo")
```

Expected behavior:

```text
Returns a compact guide object with:
- one or more relevant grammar sections
- one or more example snippets
- zero or more warnings
The function must not return the entire grammar document verbatim.
```

### Example 2: module registry lookup

Input launcher payload:

```python
[
    {
        "id": "neurocnl",
        "name": "NeuroCNL",
        "status": "running",
        "route": "/neurocnl/",
        "effectivePort": 9000,
    }
]
```

Expected behavior:

```python
client.get_module("neurocnl").effective_port == 9000
client.get_module("missing") is None
```

### Example 3: state store packet write

Input:

```python
store.write_deerflow_packet("task-123", {"task_type": "mcp_scaffold"})
```

Expected behavior:

```text
Creates a JSON file under deerflow/task-123/packet.json and read_json returns the same payload.
```

### Example 4: blueprint resources

Input:

```python
blueprint = build_server_blueprint()
```

Expected behavior:

```text
Blueprint includes at least:
- nmtk://cnl/grammar/current
- nmtk://cnl/support-matrix/current
- nmtk://suite/modules/current
- nmtk://api/openapi/current
```

### Example 5: blueprint tools

Expected tool names:

```python
{
    "validate_cnl",
    "suite_health",
    "doctor",
    "module_status",
    "get_cnl_authoring_guide",
    "run_neurocnl_simulation",
    "run_neurosim_preview",
    "check_deployability",
    "prepare_neurochip_handoff",
}
```

### Example 6: deployability boilerplate

Input:

```python
request = DeployabilityRequest(spec="neuron A spikes.", target="teensy")
```

Expected behavior:

```text
The client uses the teensy deployability route scaffold and returns a typed response.
It must not invent final production verdict labels beyond accepted/raw-response boilerplate.
```

## Edge Cases

- Missing or malformed launcher module payload
- Missing local docs for authoring-guide extraction
- Empty or unknown `intent`
- Unknown backend for authoring guide should not crash; it may return no extra warnings
- Unknown deployability target must fail clearly
- File layout creation must be idempotent
- Blueprint assembly must not import or require a concrete MCP runtime package

## Acceptance Checklist

- Matches all stated outputs
- Preserves existing foundation files
- Uses only allowed dependencies
- Keeps privileged deployment out of scope
- Does not bind to a concrete MCP runtime
- Keeps prompt content resource-oriented and low-token
