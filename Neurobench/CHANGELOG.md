# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Initial Beta Release

### Added

*   **Backend (FastAPI):**
    *   Initial API structure with routers for benchmarks, results, reports, and more.
    *   API Key authentication and rate limiting using `slowapi`.
    *   Support for benchmark execution and result reporting.
    *   Pydantic-based contracts for data validation.
*   **Frontend (Flutter):**
    *   Initial dashboard for visualizing benchmark results.
    *   Shared design system package (`nmtk_ui_core`).
    *   API client for communication with the backend.
*   **Benchmarks:**
    *   Initial set of benchmark modules for SNN performance.
    *   Support for fault injection and perturbation.
*   **Documentation:**
    *   `SECURITY.md` for vulnerability reporting.
    *   `.env.example` for backend configuration.
