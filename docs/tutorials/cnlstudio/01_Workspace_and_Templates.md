# 01: Workspace and Templates

This guide explains how to manage sessions and start projects quickly using predefined templates in CNLStudio.

## Workspace Management

A "Workspace" in CNLStudio encapsulates the active CNL specification, the currently selected hardware targets, UI layout state, and simulation configurations.

### Managing Workspace Files
- **Open Workspace:** Located in the top action bar. It opens a file dialog to select a `.nmtk` file.
  - *Agent Note:* Triggers the `_handleOpenWorkspace()` method which loads a JSON payload restoring the entire studio state.
- **Save Workspace:** Located next to the open button. It serializes the current state into a `.nmtk` file for future resumption.
- **Load/Save Spec:** If you only want to work with raw `.cnl` files rather than a full workspace, you can use the standard Load and Save text buttons.
- **Rename Active File:** Clicking on the active file name in the app bar opens a dialog to rename the file.

## The Template Gallery

Instead of starting from scratch, users can load predefined, hardware-ready network models using the **Template Gallery**.

### Accessing the Gallery
- **Visual:** Click the "Templates" or "Gallery" icon in the main UI (often presented as a grid icon or a dedicated `template_gallery.dart` widget).
- **Functionality:** Presents a categorized list of networks.

### Built-In Templates
The backend provides several default templates optimized for different use cases:
1. **Coincidence Detector:** A temporal detection network tailored for precise spike timing.
2. **Looming Detector:** A network designed for optical flow or spatial expansion, often used for collision avoidance tasks on physical robots.

### How to Apply a Template
1. Open the Template Gallery.
2. Browse or use the Search/Filter bar to find a specific template (e.g., search for "Looming").
3. Click on the template card.
4. **Warning Dialog:** A confirmation dialog will appear warning you that applying a template will overwrite the current active specification.
5. **Confirm:** Click `Apply` or `Confirm`.
  - *Agent Note:* This triggers `applyTemplateToWorkspace()`, which replaces the contents of `specTextProvider` and runs the parsing pipeline automatically.

## Best Practices
- **For Humans:** Always save your workspace before applying a new template, as it completely overwrites the active editor buffer.
- **For Agents:** When instructed to test a specific hardware flow, the fastest method is to programmatically invoke a known template (like the Coincidence Detector) and bypass manual authoring entirely.

---
*Next:* Read `02_Authoring_Networks.md` to learn how to manually write and construct CNL architectures.
