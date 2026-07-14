# Design: General-Purpose NMTK Notebook Reproduction Agent

**Date:** 2026-07-13
**Status:** Approved by user, ready for planning
**Related:** `current tasks/16 june/cnlstudio_notebook_analysis_extended.md`, `agent-tests/reproducible_notebooks.md`, `agent-tests/run_agent.sh`, `agent-tests/local_host_agent.py`

## Problem

Two separate problems found while reviewing the local GUI-automation stack used to replicate `paper/` notebooks inside the `neuro_toolkit` app:

1. `agent-tests/run_agent.sh` fails every run with `81:129: execution error: System Events got an error: AppleEvent timed out. (-1712)` — confirmed live (not just read). Root cause: the AppleScript calls in `get_window_rect_points()`/`get_screenshot()` (`local_host_agent.py`) ask System Events to activate/query the `neuro_toolkit` process, but the shell driving this script is Claude Code's own CLI process, not a windowed Terminal.app/iTerm with a real Accessibility grant — macOS can't service the AppleEvent from that context, and there's no timeout/retry/preflight to fail fast or recover.
2. The agent is currently one hardcoded macro (`run_lif_snntorch_scripted()`, default entry point) wired specifically to `paper/01_lif/lif_snntorch.ipynb`'s exact UI layout, plus a general LLM loop (`main()`, only reachable via `--llm`) that's driven by a hardcoded `TASK_INSTRUCTION` string for that same notebook and uses a text-only decision model (`qwen2.5:7b`) fed only an OmniParser element list, never the screenshot itself. Neither path generalizes to the other 9 notebooks rated reproducible in `reproducible_notebooks.md` without writing new Python per notebook.

## Solution

Make the general vision-driven loop (`main()`) the sole, default entry point, parameterized by an external per-notebook guide file instead of a hardcoded string, and upgrade its decision model to one that actually sees the screen.

### `agent-tests/local_host_agent.py`

- `OLLAMA_MODEL` → `"qwen3.5:35b"` (already pulled locally; vision + tools + thinking, 262k ctx).
- `query_llm(instruction, element_summary, history, img)`: new `img` param. Encode the cropped screenshot (PNG bytes, base64) and add it as `images: [...]` on the Ollama chat `user` message, alongside the existing text prompt. OmniParser's element list is still generated and still passed as text — it remains the source of `target_id` → click-coordinate grounding. The model now cross-references the picture with that list instead of reasoning over the list blind.
- System prompt: add one line noting a screenshot of the current app state is attached to the message.
- `TASK_INSTRUCTION` stops being a hardcoded module-level constant. `main()` takes a `guide_path` argument (first CLI positional arg), reads that file's contents as the instruction text. The existing LIF checklist text moves verbatim into `agent-tests/guides/lif_snntorch.md` as the first example guide.
- Remove `run_lif_snntorch_scripted()` and the `MODEL_TAB`/`EVAL_TAB`/`NIR_IMPORTER_ICON`/`EVAL_ADD_ICON` ratio constants and its helper functions (`click_ratio`, `parse_screen`, `find_element_by_text`, `click_element`) that exist solely to support it, since the general loop's existing action-handling in `main()` already covers click/drag/type/key/scroll/wait/done. `__main__` block simplifies to always call `main(sys.argv[1])`, erroring with a usage message if no guide path is given.
- Wrap the two AppleScript `subprocess.run(['osascript', ...])` calls in `get_window_rect_points()` and `get_screenshot()` with an AppleScript-level `with timeout of 20 seconds` block, and retry once on failure before falling back to full-screen capture (existing fallback path kept as last resort, just no longer the silent first failure mode).

### `agent-tests/run_agent.sh`

- Takes the notebook guide path as `$1` (default to `guides/lif_snntorch.md` if omitted, so existing muscle-memory invocation still works).
- Before the Ollama-serve check and before loading any OmniParser/paddle models, run a fast preflight: `osascript -e 'with timeout of 20 seconds' -e 'tell application "System Events" to get name of first process whose name is "neuro_toolkit"' -e 'end timeout'`. On failure, print an actionable error ("run this script from an actual Terminal.app window with Accessibility + Screen Recording granted to Terminal — not from an agent/CLI shell") and exit immediately, instead of failing 90+ seconds later after the heavy model loads.
- Pass the guide path through to `conda run ... python local_host_agent.py "${GUIDE_PATH}"`.

### `agent-tests/guides/`

- New `lif_snntorch.md`: the exact numbered checklist text currently hardcoded in `local_host_agent.py`, unchanged in content, just relocated.
- (Not part of this pass, noted for follow-up: guide files for the other 9 reproducible notebooks — writing those is separate work, this design only builds the mechanism that consumes them.)

## Out of scope for this pass

- Writing the other 9 notebooks' guide files.
- UI-TARS or any dedicated GUI-grounding model swap for OmniParser.
- The output-comparison / report-writing tooling that diffs NMTK's exported results against the original notebooks' results — separate follow-up task once reproduction itself is unblocked.

## Testing / Verification

- Run `agent-tests/run_agent.sh guides/lif_snntorch.md` from a real Terminal.app window (Accessibility + Screen Recording granted to Terminal) with `neuro_toolkit` running, confirm the AppleEvent preflight passes and the vision loop reaches at least the NIR-import step before manual stop.
- Confirm `qwen3.5:35b` receives the `images` field by checking Ollama's request log / a temporary debug print of payload keys.
