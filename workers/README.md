# Workers

Optional isolated processes for hardware I/O and long-running compute.
Each worker is a standalone FastAPI or CLI service started only when its
hardware or heavy dependency is present.

Workers are created in Phase 4 of the consolidation plan.
