# Quick Wins and Bugfixes - 2026-05-13

These tasks are urgent, high-impact usability fixes and minor bugs that should be addressed immediately to improve the user experience of the v0.1 release.

## 1. Workspace Load Performance / Animation
**Issue**: Loading a workspace feels slow or unresponsive.
**Task**: 
- Profile the `load workspace` operation to identify bottlenecks.
- If the delay is structural, add a sleek loading animation/overlay in the UI to provide feedback.
- Use the "Obsidian Flow" aesthetic for the loader.

## 2. Template Normal Popup
**Task**: Refactor the template selection UI to use a standard modal/popup instead of whatever non-standard implementation is currently used (if any).
- Ensure it aligns with the design system.

## 3. Layer 1 Validation Copy Cleanup
**Issue**: The UI currently duplicates the pass state by showing both the raw property label and the sentence, for example: `threshold_above_resting Invariant 'threshold_above_resting' satisfied`.
**Task**: 
- Locate the validation/diagnostic output code for Layer 1.
- Keep the success text, but render it only once.
- Normalize the display label so it reads with whitespace instead of underscores.
- Target shape: `Invariant 'threshold above resting' satisfied`.

## 4. Replace Underscores with Whitespace in Labels
**Task**: For both Layer 1 and Layer 2 property labels in the UI, replace underscores with whitespace for better readability.
- Example: `no_zero_weight_synapses` => `no zero weight synapses`.
- This should apply to the property inspector/sidebar.

## 5. Fix CNL-Canvas Sync Regression
**Task**: Prevent comment stripping and unwanted text modification when round-tripping between the editor and the graph/canvas surface.
- Preserve user-authored comments.
- Avoid injecting extra population-encoding lines unless the user explicitly requested that change.
- Keep the CNL text stable when the underlying graph has not materially changed.
