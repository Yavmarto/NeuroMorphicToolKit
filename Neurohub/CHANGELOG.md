# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-03-20

### Added
- Initial project structure for NeuroHub (FastAPI backend and Flutter frontend).
- Core orchestration logic for managing cross-app projects (NeuroSim, NeuroChip, NeuroBench, NeuroSense).
- Project dashboard with aggregated status and activity feed.
- Milestone tracking and project metadata management.
- Shared asset library for managing CNL specs, templates, and profiles.
- Workflow engine for sequential cross-app pipeline execution.
- Project export and import functionality using project bundles.
- Suite-wide health monitoring dashboard.
- Role-Based Access Control (RBAC) with API key authentication.
- Structured JSON logging and request tracing.
- Security policy (`SECURITY.md`) and environment configuration template (`.env.example`).
- Support for project-specific annotations and notes.
- Multi-stage Docker build for both backend and frontend.

### Changed
- Refined Flutter provider architecture for improved testability and dependency injection.
- Updated CORS middleware to support configurable origins via environment variables.

### Fixed
- Resolved dependency conflicts in `frontend/pubspec.yaml` related to `flutter_riverpod`.
- Corrected database persistence issues in Docker container by using named volumes.
