# NMTK Launcher (neuro_toolkit)

> **The unified entry point for neuromorphic R&D.**

Welcome to the **NMTK Launcher**—the cockpit of the NeuroMorphicToolKit suite. Designed as a robust desktop application for Windows, macOS, and Linux, the NMTK Launcher provides a seamless, unified interface for managing the entire neuromorphic development lifecycle.

---

## 🎯 The Vision

The complexity of neuromorphic toolchains—spanning Docker, Python virtual environments, and specialized hardware drivers—often creates a massive barrier to entry. The NMTK Launcher hides this complexity by acting as an **"App Store for Neuromorphic Research."** It handles installation, local orchestration, and inter-module communication, allowing users to jump from design to deployment without ever touching a terminal.

---

## 🧩 The "Cockpit" Experience

The Launcher is the sole control plane for the suite:

* **Unified Dashboard:** Browse, install, and launch specialized modules like `NeuroStudio` or `Neurobench`.
* **Workspace Management:** Seamlessly switch between projects and maintain global user profiles.
* **Health & Monitoring:** Real-time visibility into the status of local backends and hardware workers.
* **Native Surfaces:** Deeply integrated Flutter interfaces for every module, providing a premium, cohesive user experience.

---

## 🚀 Local Orchestration

Behind the scenes, the Launcher acts as a powerful daemon manager:

1.  **Dependency Management:** Automatically sets up Docker containers and isolated Python environments.
2.  **Process Control:** Spins up local micro-services (e.g., `suite_api`) on demand.
3.  **Module Manifests:** Uses a central `assets/modules.json` as the source of truth for versioning and routing.

---

## 🛠 Technical Details

### Architecture
- **Framework:** Flutter (Desktop).
- **Control Plane:** Defined in [ADR 0023](../../docs/ADR-claude/0023-nmtk-sole-control-plane-neurohub-metadata-layer.md).
- **Default API:** `suite_api` on port `9000`.

### Local Development
To run the launcher in developer mode against an existing backend:
```bash
cd nmtk/neuro_toolkit
flutter pub get
flutter run -d macos --dart-define=SUITE_API_URL=http://127.0.0.1:9000
```

### Key Files
- `assets/modules.json`: The central module manifest.
- `lib/routing/router.dart`: Global suite routing logic.
- `lib/workspace/native_surface_registry.dart`: Registration for native module surfaces.

---

## ⚖️ License
MIT
