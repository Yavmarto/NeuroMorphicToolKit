# ADR 0004: SQLite JSON Project Persistence

## Status
Accepted

## Context
Projects contain both simple metadata (name, description, timestamps) and complex structured data (graph topologies, CNL specifications). A full relational schema for graph data would be overly complex for this use case.

## Decision
Store projects in SQLite with a `CREATE TABLE IF NOT EXISTS` initialization pattern. Graph data is serialized as JSON text via Pydantic's `model_dump_json()`, preserving the full typed structure within a single TEXT column. The `ProjectStore` class manages all CRUD operations.

## Consequences
- **Positive:** Zero external database dependencies; JSON-in-SQLite preserves Pydantic model structure without an ORM while keeping queries simple for metadata fields.
- **Negative:** JSON columns cannot be indexed or queried efficiently; no schema migration tooling means manual ALTER TABLE for schema evolution.
