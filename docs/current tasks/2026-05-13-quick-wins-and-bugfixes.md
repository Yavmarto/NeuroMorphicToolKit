# Quick Wins and Bugfixes - 2026-05-13

These tasks are urgent, high-impact usability fixes and minor bugs that should be addressed immediately to improve the user experience of the v0.1 release.

## 1. Fix Simulation Bug (Nengo Decoders Cache)
**Issue**: Running simulation fails with `ApiException(500): {"error":"lowering_failed","messages":["Simulation error: [Errno 2] No such file or directory: '/nonexistent/.cache/nengo/decoders'"]}`.
**Context**: This usually happens when the backend is running in a restricted environment or container where the default Nengo cache directory (`/nonexistent/.cache`) doesn't exist or isn't writable.
**Task**: 
- Configure Nengo to use a temporary or local cache directory within the workspace or container.
- Set `nengo.rc.set('decoder_cache', 'enabled', 'False')` if caching is not strictly necessary for the simulation environment, or point it to a valid path like `/tmp/nengo_cache`.

## 2. Expose Training in UI
**Task**: Add UI affordances in the Studio screen to trigger the training process (using the recently implemented `fit()` surface).
- Add a "Train" button to the sidebar or toolbar.
- Implement a basic training configuration dialog (select adapter, epochs, etc.).
- Show training progress and results.

## 3. Workspace Load Performance / Animation
**Issue**: Loading a workspace feels slow or unresponsive.
**Task**: 
- Profile the `load workspace` operation to identify bottlenecks.
- If it's a structural delay (e.g., waiting for multiple backend probes), add a sleek loading animation/overlay in the UI to provide feedback.
- Use the "Obsidian Flow" aesthetic for the loader.

## 4. Template Normal Popup
**Task**: Refactor the template selection UI to use a standard modal/popup instead of whatever non-standard implementation is currently used (if any).
- Ensure it aligns with the design system.

## 5. Remove Redundant Layer 1 Text
**Issue**: The UI shows redundant invariant satisfaction text: `threshold_above_resting Invariant 'threshold_above_resting' satisfied`.
**Task**: 
- Locate the validation/diagnostic output code for Layer 1.
- Suppress or hide the "satisfied" messages, keeping only failures or warnings.

## 6. Replace Underscores with Whitespace in Labels
**Task**: For both Layer 1 and Layer 2 property labels in the UI, replace underscores with whitespace for better readability.
- Example: `no_zero_weight_synapses` => `no zero weight synapses`.
- This should apply to the property inspector/sidebar.
