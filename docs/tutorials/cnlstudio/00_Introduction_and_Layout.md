# 00: Introduction to CNLStudio

CNLStudio is the primary User Interface (UI) for the Neuromorphic Toolkit's Computational Network Language (`neurocnl`) suite. It provides a visual environment for designing, simulating, validating, and deploying neuromorphic architectures. 

This guide introduces the core layout and viewing modes of the Studio.

## Target Audience
- **Humans:** To understand how to navigate the application visually.
- **AI Agents (Open Claw / Open Cowork):** To understand the UI hierarchy, structural components, and how to programmatically control the workspace.

## Core Layout

The CNLStudio main screen (`StudioScreen`) is divided into several main structural areas:

1. **Top Application Bar / Action Bar:**
   - **File Operations:** Buttons for `Load Workspace`, `Save Workspace`, `Load Spec`, and `Save Spec`.
   - **View Toggles:** Switches between the `CNL` (Text) editor and `Canvas` (Visual Node) editor.
   - **Run/Stop Controls:** A central action button to parse, generate, and simulate the current network.
   - **Hardware Setup:** Access to the `Server Setup` and `Hardware Registry` dialogs.

2. **Main Editor Area (Center):**
   - Depending on the selected View Mode, this area hosts either a Text Editor for raw CNL strings or an Interactive Canvas Graph.

3. **Bottom Pipeline Bar:**
   - A visual progress bar tracking the lifecycle of the model: `Parsed` ➔ `Generated` ➔ `Simulated`.
   - It updates asynchronously as backend processes validate the spec and simulate the Network Intermediate Representation (NIR).

4. **Right Side Panels (The Tool Drawer):**
   - A vertical set of tabs or accordion panels offering deep analysis, simulation charts, and hardware deployment options.
   - Example panels include: `Parsed Specs`, `Validation`, `Simulate`, `Compare`, and `Deploy`.

## View Modes

CNLStudio offers a bidirectional sync engine that translates between text and visual representations.

### 1. CNL Mode (Text Editor)
- **Visual:** A code editor with line numbers and syntax highlighting.
- **Purpose:** Direct authoring of the Computational Network Language. It provides full control over comments and metadata.
- **Agent Note:** Agents can directly inject raw CNL strings into this editor or use the Sentence Builder dialog.

### 2. Canvas Mode (Visual Editor)
- **Visual:** A 2D draggable node-graph interface.
- **Purpose:** Intuitive drag-and-drop authoring. Nodes represent Populations (e.g., LIF, Izhikevich neurons) and edges represent Projections.
- **Agent Note:** Actions taken in the Canvas are automatically translated into CNL text in the background via the bidirectional sync engine (`_syncCanvasToCnl`).

## The Flow of Operations
A typical workflow in CNLStudio involves:
1. **Authoring:** Writing CNL or placing nodes on the Canvas.
2. **Validating:** Checking the `Validation Panel` and `Parse Results` for syntax and topological errors.
3. **Simulation:** Running a test simulation and observing the `Simulation Dashboard` (Energy & Sensors).
4. **Deployment:** Selecting a target (Teensy, PYNQ, Akida) from the `Deploy` panel and exporting the artifact.

---
*Next:* Read `01_Workspace_and_Templates.md` to learn how to manage files and load predefined network templates.
