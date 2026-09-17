# ADR 0005: Artifact Versioning

## Status
Accepted

## Context
Community members need to share, version, and discover SNN models, encoding presets, hardware profiles, and benchmark baselines. Artifacts evolve over time and users need access to specific versions.

## Decision
Implement `SharedAssetDB` with integer-based versioning, type-based indexing, and an `asset_library.py` service for CRUD operations. Asset content is stored as JSON with optional file attachments. A `bundle_service.py` supports grouped export and import of related artifacts as a single archive.

## Consequences
- **Positive:** Integer versioning is simple and unambiguous; bundle export/import enables portable sharing of complete experiment configurations.
- **Negative:** Integer versioning lacks the semantic meaning of semver (breaking vs. non-breaking changes); no dependency tracking between assets that reference each other.
