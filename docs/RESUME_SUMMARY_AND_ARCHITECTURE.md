# Professional Summary & Technical Architecture

This document summarizes the core accomplishments and architectural decisions for the **NeuroMorphicToolkit (NMTK)** and associated projects (OIGS). It is designed to serve as a comprehensive reference for resume building and technical interview preparation.

---

## 👨‍💻 Professional Profile
**The Narrative:** A unique bridge between **Behavioral Science** and **Silicon**. Leveraging a **Psychology Master's** to design biologically plausible learning systems, an **AI Master's** to implement advanced machine learning, and **7+ years of Senior Engineering** to build robust, scalable platforms.

---

## 🚀 Key Project: NeuroMorphicToolkit (NMTK)
*Lead Architect & Senior Software Engineer*

**High-Level Impact:**
Architected a cross-disciplinary platform unifying **Computational Neuroscience**, **AI Research**, and **Edge Robotics**. The suite enables the design, simulation, and deployment of Spiking Neural Networks (SNNs) to physical hardware through a unified "Mission Control" desktop interface.

### **Core Accomplishments:**
*   **DSL Design (NeuroCNL):** Created the *Conceptual Neuromorphic Language*, a DSL translating natural language to verified SNNs with **18+ physics invariants**.
*   **Agentic CDD Pipeline:** Pioneered a **Contract-Driven Development (CDD)** and **Property-Based Testing (PBT)** migration pipeline, automating **150+ requirements** across 7 modules.
*   **Hardware-in-the-Loop (HITL):** Built the bridge for **Teensy 4.1** and **OpenBCI Ganglion**, deploying real-time sensory-motor control and BCI learning agents.
*   **Hybrid Orchestration:** Engineered a **Flutter-based desktop suite** that orchestrates **Dockerized Python backends**, enabling direct, bidirectional translation between CNL and the Neuromorphic Intermediate Representation (NIR) for hardware-agnostic deployments.

---

## 🏗️ Technical Architecture Deep-Dive

### **1. The Orchestrator Shell Pattern**
The suite is designed as a **Hybrid Micro-Service Desktop application**.
*   **Host Environment:** Flutter Desktop (macOS/Windows/Linux) acts as the local daemon manager.
*   **Isolation Strategy:** Heavy scientific dependencies (Nengo, PyTorch, MuJoCo) are isolated in **Docker Containers** or **Python Virtual Environments**, managed by the shell's `ProcessManager`.
*   **Why?** This solves the "Dependency Hell" inherent in neuromorphic engineering, where research libraries often have conflicting version requirements.

### **2. Integration & Communication**
*   **The Module Manifest:** A declarative `modules.json` registry handles port assignments, health monitoring, and capability reporting.
*   **Cross-Module Handoff:** Inter-module communication (IMC) is handled via deep links and REST-based state injection.
    *   *Example:* Moving a spec from NeuroCNL to NeuroSim triggers a shell-intercepted navigation that POSTs the validated design to the simulation engine.
*   **Warm-Session Switching:** Uses Flutter's `IndexedStack` to keep background module views alive, making switches between simulation and code feel instantaneous.

### **3. Engineering Excellence**
*   **Contract-Driven Development (CDD):** Used **Pydantic v2** to define strict boundaries between modules. Build-time verification ensures changes in one module (e.g., a compiler update) don't break downstream consumers (e.g., a hardware flasher).
*   **Property-Based Testing (PBT):** Leveraged **Hypothesis** to fuzz-test physics pipelines. 
    *   *Verification:* Ensuring "Dale's Law" (neurons are purely excitatory/inhibitory) and membrane potential decay are maintained regardless of input edge cases.
*   **Agentic Governance:** Implemented `AGENTS.md` and `GUARDRAILS.md` to guide AI-driven implementation, ensuring automated code generation adheres to project-specific architecture patterns.

---

## 🛠️ Technical Skills

*   **Neuromorphic:** SNN Design, STDP, Nengo, Intel Lava, SpiNNaker2, BrainChip Akida.
*   **AI/ML:** Reinforcement Learning (PPO), LLM Agent Orchestration, Pydantic v2, Signal Processing.
*   **Full-Stack:** Flutter (Desktop), Dart, Python (FastAPI/Pyramid), TypeScript (NestJS, Next.js), Docker.
*   **Embedded:** Teensy 4.1 (C++), OpenBCI Ganglion, EMG/EEG Processing, PYNQ Z2.
*   **DevOps:** CI/CD Guardrails, Automated Regression (Golden Baselines), Gherkin/BDD.

---

## 💬 Technical Interview Cheat Sheet

### **Q: How do you handle a module backend crashing?**
**A:** "I implemented a **Readiness Model**. The shell probes a `/health` endpoint for each module. If it fails, the UI transitions to a 'Degraded State' or 'Error State' (Preflight Failed), isolating the failure and providing recovery actions without crashing the entire suite."

### **Q: Why use Docker for local desktop modules?**
**A:** "Scientific Python environments are notoriously fragile. Docker ensures **environment parity** across developer machines and production. It allows us to ship 10GB+ of ML dependencies as pre-built images rather than forcing the user to manage complex `pip` or `conda` installs."

### **Q: How does the "Open in NeuroSim" button actually work technically?**
**A:** "It's a two-stage handoff. First, the shell intercepts the navigation request from the NeuroCNL WebView. Second, it uses the **Control API Service** to push the current session's validated IR (Intermediate Representation) to the NeuroSim backend via a local REST call, then focuses the NeuroSim tab."

### **Q: How do you ensure real-time performance on the Teensy?**
**A:** "We use a **Static Allocation** strategy. Our compiler emits network parameters as C++ headers with fixed-size arrays. This avoids heap fragmentation and ensures deterministic execution times for the LIF (Leaky Integrate-and-Fire) update loop."
