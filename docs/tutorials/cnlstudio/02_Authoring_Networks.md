# 02: Authoring Networks

CNLStudio provides multiple distinct ways to build and edit Neuromorphic architectures. This guide covers how to construct networks using the Text Editor, the Visual Canvas, and the guided Sentence Builder.

## 1. The CNL Editor (Text Mode)
The primary interface for power users is the `CNL Editor`. It is a text-based code editor specifically built for the Computational Network Language.

### Features
- **Syntax Highlighting:** Keywords (like `Create`, `Connect`), object names, and parameters are color-coded for readability.
- **Error Boundaries:** If the backend parser detects syntax errors, red squiggly lines or error boundaries will appear to guide corrections.
- **Direct Control:** Editing raw text provides the most fine-grained control over network topologies, weights, and comments.
- **Agent Note:** Located in `cnl_editor.dart`. Agents should inject raw strings directly into this editor surface when tasked with writing custom models.

## 2. The Canvas (Visual Node Mode)
For users who prefer visual diagramming, CNLStudio offers the **Canvas**.

### Features
- **Nodes and Edges:** Users can drag blocks (representing Neuron Populations or Inputs) onto the canvas and draw lines (Projections) between them.
- **Parameter Menus:** Clicking on a node opens a side panel or modal to adjust neuron parameters (e.g., threshold, decay, refractory period).
- **Bidirectional Sync:** The Canvas is not isolated! As you drag nodes or change parameters, the system automatically translates the visual graph into CNL code in the background. If you switch back to the Text Editor, your visual changes are perfectly preserved as code.

## 3. CNL Sentence Builder Dialog
The **Sentence Builder Dialog** is a guided UI designed to help beginners construct valid CNL commands without memorizing the syntax.

### How it Works
- **Access:** Typically launched via a `+ Add Sentence` or `Build Command` button near the editor.
- **Guided Form:** It presents dropdowns and fill-in-the-blank forms. For example:
  - *Action:* `Create`
  - *Type:* `Population`
  - *Name:* `[ user input ]`
  - *Parameters:* `[ parameter explorer ]`
- **Output:** Once the form is completed, the dialog generates a syntactically perfect CNL sentence and inserts it into the current cursor position in the Text Editor.

## Best Practices
- **For Humans:** If you are unsure of the correct syntax for a specific neuron model (like Izhikevich or LIF), use the **Sentence Builder Dialog** to generate the boilerplate.
- **For Agents:** When debugging a complex network, reading the raw CNL text is often much more reliable and deterministic than attempting to parse the DOM of the Canvas visual graph. Always default to interacting with the Text Editor (`specTextProvider`) when making structural changes.

---
*Next:* Read `03_Analysis_and_Validation.md` to learn how to check your network for errors and view structural metrics.
