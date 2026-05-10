# Interfaces

Document only signatures, types, schemas, and stub bodies here.

Guidelines:

- Keep names generic when names reveal sensitive business meaning.
- Include enough type information to implement the task correctly.
- Remove internal logic.
- Mark omitted logic with `TODO` or `pass`.
- If the task must mirror existing repo behavior, include the smallest stub surface that still exposes the relevant semantics.

Example:

```python
from dataclasses import dataclass


@dataclass
class DataPayload:
    identifier: str
    values: list[float]


class Processor:
    def process_data(self, payload: DataPayload) -> float:
        """Return the 95th percentile of payload values."""
        raise NotImplementedError
```

# Stub Files

If the task is easier as a patch, paste sanitized stub files below under separate headings.

## stub_module.py

```python
# Paste sanitized stub here.
```

## Reference Notes

Add short sanitized notes here only when DeerFlow must mirror an existing implementation detail
that cannot be inferred safely from the stub alone.

Examples:

- "Unsupported `local_radius` patterns must raise a clear error instead of lowering approximately."
- "`binary_mask` is executable; do not classify it as metadata-only."
