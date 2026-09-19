# NMTK Notebook Agent — General Vision Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `agent-tests/local_host_agent.py` + `agent-tests/run_agent.sh` from a single hardcoded macro for one notebook into a general vision-driven agent that takes a per-notebook guide file as an argument, sees the screenshot itself (via `qwen3.5:35b`), and fails fast with an actionable message instead of a 90-second-late AppleEvent timeout.

**Architecture:** Keep OmniParser for click-target grounding (bounding boxes from icon-detect+OCR). Replace the text-only decision model with a vision model fed the same cropped screenshot the human would see. Replace the hardcoded `TASK_INSTRUCTION` string with a CLI-supplied guide file path. Wrap the two System-Events AppleScript calls in a timeout+retry, and add a fast preflight check in the shell launcher before any heavy model loads.

**Tech Stack:** Python 3.12 (conda env `omni`), Ollama (`qwen3.5:35b`, local, port 11435), OmniParser (YOLO + Florence-2 + EasyOCR), pyautogui, mss, pytest 8.3.3 (already installed in `omni`), bash.

## Global Constraints

- `OLLAMA_MODEL` must be `"qwen3.5:35b"` (vision+tools+thinking, already pulled — confirmed via `ollama list`).
- No new pip/conda installs — every library used below is already present in the `omni` env (verified: `torch`, `pytest`, `requests`, `pyautogui`, `mss`, `PIL`).
- `run_lif_snntorch_scripted()` and its four ratio constants (`MODEL_TAB`, `EVAL_TAB`, `NIR_IMPORTER_ICON`, `EVAL_ADD_ICON`) and helpers (`click_ratio`, `parse_screen`, `find_element_by_text`, `click_element`) are deleted — general loop replaces them entirely.
- `TASK_INSTRUCTION` is no longer a module constant — it is loaded at runtime from a file path given as `sys.argv[1]`.
- Existing action schema in `query_llm`'s system prompt (`click`/`type`/`key`/`drag`/`scroll`/`wait`/`done`) is unchanged — only the `images` field and one prompt line are added.
- AppleScript calls get `with timeout of 20 seconds` and one retry before any fallback path fires.

---

### Task 1: Relocate the LIF task instruction into a guide file

**Files:**
- Create: `agent-tests/guides/lif_snntorch.md`
- Test: `agent-tests/test_local_host_agent.py` (new file, created in this task)

**Interfaces:**
- Produces: `agent-tests/guides/lif_snntorch.md` — plain text file, content is the exact current `TASK_INSTRUCTION` string body (no Python string escaping, just the raw checklist text).
- Produces: `load_guide(path: str) -> str` function (to be added to `local_host_agent.py` in Task 3) — later tasks and the test in this task assume this signature: takes a file path, returns its stripped text content, raises `FileNotFoundError` with a clear message if missing.

- [ ] **Step 1: Create the guide file**

Content (copied verbatim from the current `TASK_INSTRUCTION` constant, lines 39-71 of `agent-tests/local_host_agent.py`, with the f-string's `{NIR_FILE_PATH}` resolved to its literal value):

```markdown
You are reproducing the 'lif_snntorch.ipynb' notebook inside the NeuroStudio (neuro_toolkit) application by following this EXACT numbered checklist, in order. Use the action history below to figure out which steps you've already completed, then perform the next uncompleted one. Do not skip ahead and do not repeat a step that already succeeded.

Canvas: Model
1. Navigate to the Model Canvas (stepper tab '2. Model').
2. Click the icon whose tooltip/content is 'NIR Importer' to open its side panel.
3. Inside that panel, click the button labeled 'Load .nir'.
4. A native file picker will open as a SEPARATE window you cannot see or click into — do not try. Instead: press key 'cmd+shift+g', then type the exact text '$HOME/NeuroMorphicToolKit/paper/01_lif/lif_norse.nir', then press key 'Return', then press key 'Return' again to confirm the file selection.
5. Wait a couple of seconds, then confirm the Model canvas now shows a real graph (no longer empty).

Canvas: Eval
6. Navigate to the Eval Canvas (stepper tab '4. Eval').
7. Click the '+' icon in the bottom toolbar (tooltip 'Add') to open the 'Add Node' picker.
8. Click the tile labeled 'Spike Generator'. Configure it: n_neurons=1, n_timesteps=100, pattern=isi_regular, isi_period=10, seed=42.
9. Click the '+' icon again, then click the tile labeled 'State Reset'.
10. Click the '+' icon again, then click the tile labeled 'Forward Pass'. Set its eval_mode = true.
11. Click the '+' icon again, then click the tile labeled 'Spike Rate Logger'.
12. Drag from the Spike Generator node's output port to the Forward Pass node's input port (use the 'drag' action with from_id/to_id set to those two ports' element IDs).
13. Drag from the State Reset node's model-output port to the Forward Pass node's model-input port.
14. Drag from the Forward Pass node's spikes-output port to the Spike Rate Logger node's spikes-input port. Leave any other Forward Pass outputs (membrane, model) unconnected.
15. Click 'Run Eval'.

Results Step: Dynamics Tab
16. After the eval run completes, navigate to the Results step and open the Dynamics tab.
17. Confirm the Spike Raster panel shows the output spike times.
18. Confirm the Membrane Voltage Trace panel shows the LIF membrane potential over 100 timesteps.
19. Export results to CSV via the export button.
```

- [ ] **Step 2: Create the test file with a failing test for `load_guide`**

```python
# agent-tests/test_local_host_agent.py
"""Unit tests for local_host_agent.py that don't require the GUI, Ollama,
or OmniParser to be running. Run with: conda run -n omni pytest agent-tests/test_local_host_agent.py -v
"""
import base64
import subprocess
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

import local_host_agent as agent


def test_load_guide_reads_file_content(tmp_path):
    guide = tmp_path / "sample_guide.md"
    guide.write_text("1. Do the thing.\n2. Do the other thing.\n")
    result = agent.load_guide(str(guide))
    assert result == "1. Do the thing.\n2. Do the other thing."


def test_load_guide_missing_file_raises_filenotfounderror():
    with pytest.raises(FileNotFoundError, match="Guide file not found"):
        agent.load_guide("/nonexistent/path/does_not_exist.md")
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd agent-tests && conda run -n omni pytest test_local_host_agent.py -v`
Expected: FAIL with `AttributeError: module 'local_host_agent' has no attribute 'load_guide'`

(Task 3 adds `load_guide` to `local_host_agent.py`; this test starts passing once that lands. Do not skip ahead — commit the guide file and test now, the function comes in Task 3.)

- [ ] **Step 4: Commit**

```bash
cd $HOME/NeuroMorphicToolKit
git add agent-tests/guides/lif_snntorch.md agent-tests/test_local_host_agent.py
git commit -m "test: add lif_snntorch guide file and agent test scaffold"
```

---

### Task 2: Add vision payload support to `query_llm`

**Files:**
- Modify: `agent-tests/local_host_agent.py:168-223` (the `query_llm` function)
- Test: `agent-tests/test_local_host_agent.py` (append)

**Interfaces:**
- Consumes: nothing new from other tasks.
- Produces: `query_llm(instruction: str, element_summary: str, history: list, img: "PIL.Image.Image") -> dict` — signature changes from 3 params to 4 (img added last). Task 5 (the `main()` loop) will be updated to call it with the screenshot it already has in scope.

- [ ] **Step 1: Write the failing test**

```python
# append to agent-tests/test_local_host_agent.py
from PIL import Image


def _make_fake_img():
    return Image.new("RGB", (4, 4), color=(255, 0, 0))


def test_query_llm_sends_base64_image_in_payload():
    fake_response = MagicMock()
    fake_response.raise_for_status = MagicMock()
    fake_response.json.return_value = {"message": {"content": '{"action":"wait","reason":"test"}'}}

    with patch("local_host_agent.requests.post", return_value=fake_response) as mock_post:
        result = agent.query_llm("do the task", "0\tbutton\tOK", [], _make_fake_img())

    assert result == {"action": "wait", "reason": "test"}
    sent_payload = mock_post.call_args.kwargs["json"]
    assert "images" in sent_payload["messages"][-1]
    encoded = sent_payload["messages"][-1]["images"][0]
    # must be valid base64
    base64.b64decode(encoded)


def test_query_llm_model_is_qwen3_5_35b():
    assert agent.OLLAMA_MODEL == "qwen3.5:35b"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd agent-tests && conda run -n omni pytest test_local_host_agent.py -v -k query_llm`
Expected: FAIL — `test_query_llm_sends_base64_image_in_payload` fails with `TypeError: query_llm() takes 3 positional arguments but 4 were given` (or similar), `test_query_llm_model_is_qwen3_5_35b` fails on the `assert` since the constant is still `qwen2.5:7b`.

- [ ] **Step 3: Implement — update `OLLAMA_MODEL` and `query_llm`**

Replace line 21:
```python
OLLAMA_MODEL = "qwen2.5:7b"          # fast + reliable JSON output
```
with:
```python
OLLAMA_MODEL = "qwen3.5:35b"         # vision-capable — sees the screenshot, not just the element list
```

Replace the full `query_llm` function (original lines 168-223) with:

```python
def query_llm(instruction: str, element_summary: str, history: list, img: Image.Image) -> dict:
    """
    Ask the LLM for the next GUI action. `img` is the current cropped
    screenshot (PIL Image) — sent alongside the text prompt so the model
    reasons over pixels and the OmniParser element list together.
    Returns a dict with keys: action, target_id (optional), text (optional).
    """
    system_prompt = (
        "You are a GUI automation agent. A screenshot of the current application "
        "window is attached to this message — use it together with the element list "
        "below to decide where to click or drag.\n"
        "You MUST reply with ONLY valid JSON, no markdown, no extra text.\n"
        "Actions available:\n"
        '  {"action":"click","target_id":"<element ID number as string>"}\n'
        '  {"action":"type","text":"<text to type>"}\n'
        '  {"action":"key","text":"<key combo, e.g. shift+Return or cmd+shift+g>"}\n'
        '  {"action":"drag","from_id":"<element ID to drag from>","to_id":"<element ID to drag to>"}\n'
        '  {"action":"scroll","direction":"down","amount":3}\n'
        '  {"action":"done","reason":"<why task is complete>"}\n'
        '  {"action":"wait","reason":"<why waiting>"}\n'
        "If the history shows your last action had NO EFFECT on the screen, do not repeat it — "
        "that element is not the right one, pick a different element or approach.\n"
    )

    history_block = "\n".join(history[-5:]) if history else "(no actions taken yet)"

    user_prompt = (
        f"TASK: {instruction}\n\n"
        f"RECENT ACTION HISTORY:\n{history_block}\n\n"
        f"SCREEN ELEMENTS (ID \\t type \\t content):\n{element_summary}\n\n"
        "What is the SINGLE next action to take? Reply with ONLY JSON."
    )

    buf = io.BytesIO()
    img.save(buf, format="PNG")
    encoded_img = base64.b64encode(buf.getvalue()).decode("ascii")

    payload = {
        "model": OLLAMA_MODEL,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt, "images": [encoded_img]},
        ],
        "format": "json",
        "stream": False,
        "options": {"temperature": 0.1, "num_ctx": 8192},
    }

    try:
        resp = requests.post(OLLAMA_URL, json=payload, timeout=120)
        resp.raise_for_status()
        raw = resp.json()["message"]["content"]
        raw = re.sub(r"```(?:json)?|```", "", raw).strip()
        return json.loads(raw)
    except requests.HTTPError as e:
        print(f"  [LLM HTTP error] {e} — status {e.response.status_code}")
        print(f"  Response body: {e.response.text[:300]}")
        return {"action": "error"}
    except json.JSONDecodeError as e:
        print(f"  [LLM JSON parse error] {e}")
        return {"action": "error"}
    except Exception as e:
        print(f"  [LLM error] {e}")
        return {"action": "error"}
```

Add `import base64` and `import io` to the top of `agent-tests/local_host_agent.py` (with the other stdlib imports, near `import re`).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd agent-tests && conda run -n omni pytest test_local_host_agent.py -v -k query_llm`
Expected: PASS (2 passed)

- [ ] **Step 5: Commit**

```bash
cd $HOME/NeuroMorphicToolKit
git add agent-tests/local_host_agent.py agent-tests/test_local_host_agent.py
git commit -m "feat: switch decision model to qwen3.5:35b and send screenshot to it"
```

---

### Task 3: Add `load_guide`, remove the scripted macro, make `main()` guide-driven

**Files:**
- Modify: `agent-tests/local_host_agent.py` (remove lines 29-71 constants block, remove `run_lif_snntorch_scripted` and its dedicated helpers at lines 235-369, update `main()` signature and body, update `__main__` block at lines 556-564)

**Interfaces:**
- Consumes: `load_guide` (defined here, used by test written in Task 1).
- Produces: `main(guide_path: str)` — takes the guide file path explicitly (previously `main()` took no args and read the module-level `TASK_INSTRUCTION` constant).

- [ ] **Step 1: Write the failing test**

```python
# append to agent-tests/test_local_host_agent.py

def test_scripted_macro_removed():
    assert not hasattr(agent, "run_lif_snntorch_scripted")


def test_main_requires_guide_path_argument():
    import inspect
    sig = inspect.signature(agent.main)
    assert list(sig.parameters) == ["guide_path"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd agent-tests && conda run -n omni pytest test_local_host_agent.py -v -k "scripted_macro_removed or main_requires_guide_path"`
Expected: FAIL — `run_lif_snntorch_scripted` still exists; `main`'s signature is currently `()`.

- [ ] **Step 3: Implement**

Delete the entire block from the `NIR_FILE_PATH = ...` line through the end of `TASK_INSTRUCTION`'s closing `)` (original lines 29-71) — this text now lives in `agent-tests/guides/lif_snntorch.md` (Task 1).

Delete the entire "Scripted routine" section (original lines 235-369): the comment block, `MODEL_TAB`/`EVAL_TAB`/`NIR_IMPORTER_ICON`/`EVAL_ADD_ICON`, `click_ratio`, `parse_screen`, `find_element_by_text`, `click_element`, and `run_lif_snntorch_scripted` in full.

Add this function above `main()` (near the other helpers, e.g. right after `element_center_px`):

```python
def load_guide(path: str) -> str:
    """Read a per-notebook task-instruction guide file and return its text,
    stripped of leading/trailing whitespace. Raises FileNotFoundError with an
    actionable message if the path doesn't exist."""
    guide_file = Path(path)
    if not guide_file.is_file():
        raise FileNotFoundError(
            f"Guide file not found: {path!r}. Pass the path to a notebook "
            f"guide, e.g. agent-tests/guides/lif_snntorch.md"
        )
    return guide_file.read_text().strip()
```

Update `main()`'s signature (originally `def main():`) to:

```python
def main(guide_path: str):
    task_instruction = load_guide(guide_path)

    report_lines = [
        f"# Notebook Reproduction Report",
        f"Generated: {datetime.now().isoformat()}",
        f"Guide: {guide_path}",
        "",
        f"## Task",
        task_instruction,
        "",
        "## Steps",
    ]
```

(This replaces the original `report_lines` block that referenced module-level `TASK_INSTRUCTION` — every other later reference to `TASK_INSTRUCTION` inside `main()`'s loop body must be changed to `task_instruction`. There is exactly one: the `query_llm(TASK_INSTRUCTION, element_summary, history)` call — update it in Task 4 alongside the `img` argument, since both changes touch the same line.)

Replace the trailing `if __name__ == "__main__":` block (original lines 556-564) with:

```python
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python local_host_agent.py <path-to-guide.md>")
        print("Example: python local_host_agent.py guides/lif_snntorch.md")
        sys.exit(1)
    main(sys.argv[1])
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd agent-tests && conda run -n omni pytest test_local_host_agent.py -v`
Expected: PASS (all tests so far, including Task 1's `load_guide` tests)

- [ ] **Step 5: Commit**

```bash
cd $HOME/NeuroMorphicToolKit
git add agent-tests/local_host_agent.py agent-tests/test_local_host_agent.py
git commit -m "refactor: drop scripted macro, make main() guide-driven"
```

---

### Task 4: Wire the screenshot into `main()`'s `query_llm` call

**Files:**
- Modify: `agent-tests/local_host_agent.py` (inside `main()`'s loop, original line 447)

**Interfaces:**
- Consumes: `query_llm(instruction, element_summary, history, img)` from Task 2, `task_instruction` local variable from Task 3.
- Produces: nothing new — this is the call-site wiring that makes Tasks 2 and 3 actually connect.

- [ ] **Step 1: Write the failing test**

```python
# append to agent-tests/test_local_host_agent.py

def test_main_passes_screenshot_to_query_llm(tmp_path, monkeypatch):
    guide = tmp_path / "g.md"
    guide.write_text("1. Click done.")

    fake_img = _make_fake_img()

    def fake_get_screenshot():
        return fake_img, 100, 100, (0, 0)

    monkeypatch.setattr(agent, "get_screenshot", fake_get_screenshot)
    monkeypatch.setattr(agent, "save_screenshot", lambda *a, **k: "fake/path.png")
    monkeypatch.setattr(agent, "get_yolo_model", lambda **k: MagicMock())
    monkeypatch.setattr(agent, "get_caption_model_processor", lambda **k: MagicMock())

    def fake_check_ocr_box(*a, **k):
        return (([], []), None)

    monkeypatch.setattr(agent, "check_ocr_box", fake_check_ocr_box)
    monkeypatch.setattr(agent, "get_som_labeled_img", lambda *a, **k: (None, {}, []))

    captured = {}

    def fake_query_llm(instruction, element_summary, history, img):
        captured["img"] = img
        captured["instruction"] = instruction
        return {"action": "done", "reason": "test finished"}

    monkeypatch.setattr(agent, "query_llm", fake_query_llm)
    monkeypatch.setattr(agent.time, "sleep", lambda *_: None)

    agent.main(str(guide))

    assert captured["img"] is fake_img
    assert captured["instruction"] == "1. Click done."
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd agent-tests && conda run -n omni pytest test_local_host_agent.py -v -k test_main_passes_screenshot`
Expected: FAIL — `TypeError: fake_query_llm() missing 1 required positional argument: 'img'` (current call site only passes 3 args).

- [ ] **Step 3: Implement**

In `main()`'s loop, find:
```python
        action_obj = query_llm(TASK_INSTRUCTION, element_summary, history)
```
Replace with:
```python
        action_obj = query_llm(task_instruction, element_summary, history, img)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd agent-tests && conda run -n omni pytest test_local_host_agent.py -v`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
cd $HOME/NeuroMorphicToolKit
git add agent-tests/local_host_agent.py
git commit -m "fix: pass live screenshot into query_llm from main() loop"
```

---

### Task 5: AppleScript timeout + retry in `get_window_rect_points` / `get_screenshot`

**Files:**
- Modify: `agent-tests/local_host_agent.py:76-133` (`get_window_rect_points`, `get_screenshot`)

**Interfaces:**
- Consumes: nothing new.
- Produces: `get_window_rect_points()` unchanged return type (`(x, y, w, h)` tuple or `None`); `get_screenshot()` unchanged return type (`(img, w_pt, h_pt, origin)`). Behavior changes only — same call sites, no signature change, so no other task depends on new interface shape.

- [ ] **Step 1: Write the failing test**

```python
# append to agent-tests/test_local_host_agent.py

def test_get_window_rect_points_retries_once_on_timeout():
    timeout_result = MagicMock(returncode=1, stdout="", stderr="AppleEvent timed out")
    ok_result = MagicMock(returncode=0, stdout="{100, 200}, {800, 600}", stderr="")

    with patch("local_host_agent.subprocess.run", side_effect=[timeout_result, ok_result]) as mock_run:
        result = agent.get_window_rect_points()

    assert result == (100.0, 200.0, 800.0, 600.0)
    assert mock_run.call_count == 2


def test_get_window_rect_points_uses_applescript_timeout_wrapper():
    ok_result = MagicMock(returncode=0, stdout="{0, 0}, {10, 10}", stderr="")
    with patch("local_host_agent.subprocess.run", return_value=ok_result) as mock_run:
        agent.get_window_rect_points()
    script_arg = mock_run.call_args.args[0][2]  # ['osascript', '-e', <script>]
    assert "with timeout of 20 seconds" in script_arg
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd agent-tests && conda run -n omni pytest test_local_host_agent.py -v -k get_window_rect_points`
Expected: FAIL — current implementation calls `subprocess.run` exactly once with no retry, and its AppleScript string has no `with timeout of`.

- [ ] **Step 3: Implement**

Replace `get_window_rect_points()` (original lines 76-94) with:

```python
def get_window_rect_points():
    """Return (x, y, w, h) in points for neuro_toolkit's front window, or None
    if it can't be determined (e.g. Accessibility permission not granted).
    Wrapped in a 20s AppleScript-level timeout and retried once, since a cold
    app or a busy System Events can otherwise hit AppleEvent error -1712
    well before Python's own subprocess timeout would fire."""
    script = (
        'with timeout of 20 seconds\n'
        'tell application "System Events" to tell process "neuro_toolkit" '
        'to get {position, size} of front window\n'
        'end timeout'
    )
    for attempt in range(2):
        try:
            result = subprocess.run(
                ['osascript', '-e', script],
                capture_output=True, text=True, timeout=25,
            )
        except subprocess.TimeoutExpired:
            continue
        if result.returncode == 0:
            nums = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", result.stdout)]
            if len(nums) == 4:
                x, y, w, h = nums
                return x, y, w, h
        if attempt == 0:
            print("  ⚠️  System Events call failed/timed out, retrying once…")
            time.sleep(1)
    return None
```

Replace the `get_screenshot()` activation call (original lines 97-104) — the `subprocess.run(['osascript', ...])` at line 103 — with a timeout-wrapped, retried version. Full updated `get_screenshot()`:

```python
def get_screenshot():
    # Force the app to the foreground before every screenshot.
    # NOTE: do NOT send "reopen" here — that Apple Event is for restoring a
    # window when the app has none visible, and Flutter's macOS embedder
    # mishandles it even when a window is already open, knocking it out of
    # view and leaving only the menu bar for OmniParser to see.
    activate_script = (
        'with timeout of 20 seconds\n'
        'tell application "neuro_toolkit" to activate\n'
        'tell application "System Events" to set frontmost of process "neuro_toolkit" to true\n'
        'end timeout'
    )
    for attempt in range(2):
        try:
            result = subprocess.run(['osascript', '-e', activate_script], capture_output=True, text=True, timeout=25)
        except subprocess.TimeoutExpired:
            result = None
        if result is not None and result.returncode == 0:
            break
        if attempt == 0:
            print("  ⚠️  Could not activate neuro_toolkit (AppleEvent issue), retrying once…")
            time.sleep(1)
    time.sleep(3)

    win_rect_pt = get_window_rect_points()

    with mss.MSS() as sct:
        monitor = sct.monitors[1]
        pt_w, pt_h = pyautogui.size()

        if win_rect_pt is not None:
            # Crop the capture to just the app's own window so OmniParser can
            # never see (or click) the menu bar / Notification Center / Dock.
            # `scale` assumes one uniform physical-pixels-per-point ratio,
            # true for this single-display Retina setup.
            scale = monitor["width"] / pt_w
            x_pt, y_pt, w_pt, h_pt = win_rect_pt
            region = {
                "left": monitor["left"] + int(x_pt * scale),
                "top": monitor["top"] + int(y_pt * scale),
                "width": int(w_pt * scale),
                "height": int(h_pt * scale),
            }
            shot = sct.grab(region)
            img = Image.frombytes("RGB", shot.size, shot.bgra, "raw", "BGRX")
            return img, w_pt, h_pt, (x_pt, y_pt)

        print("  ⚠️  Could not read neuro_toolkit's window bounds (check Accessibility "
              "permission) — falling back to full-screen capture; the agent may see the menu bar.")
        shot = sct.grab(monitor)
        img = Image.frombytes("RGB", shot.size, shot.bgra, "raw", "BGRX")
        return img, pt_w, pt_h, (0, 0)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd agent-tests && conda run -n omni pytest test_local_host_agent.py -v`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
cd $HOME/NeuroMorphicToolKit
git add agent-tests/local_host_agent.py
git commit -m "fix: wrap AppleScript calls in 20s timeout with one retry"
```

---

### Task 6: `run_agent.sh` — guide-path argument + fast AppleEvent preflight

**Files:**
- Modify: `agent-tests/run_agent.sh` (full file, 65 lines)

**Interfaces:**
- Consumes: `local_host_agent.py`'s new `sys.argv[1]` guide-path requirement (Task 3).
- Produces: nothing consumed by later tasks — this is the last task.

- [ ] **Step 1: There is no automated test for this file** (it's a bash launcher that shells out to `osascript`/`conda run`/GUI apps — no pytest harness fits). Verification is manual, in Step 3 below.

- [ ] **Step 2: Implement**

Replace the full contents of `agent-tests/run_agent.sh` with:

```bash
#!/bin/bash
# NMTK Notebook Reproduction Agent — Launcher
# Usage: ./agent-tests/run_agent.sh [path/to/guide.md]
#   Defaults to guides/lif_snntorch.md if no guide path is given.
# The agent will auto-focus the neuro_toolkit app. You do NOT need to switch manually.
#
# IMPORTANT: run this from an actual Terminal.app (or iTerm) window, not from
# inside an agent/CLI shell (e.g. Claude Code) — the AppleEvent preflight
# below needs Accessibility + Screen Recording granted to a real windowed
# terminal app to succeed.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_TESTS_DIR="${PROJECT_ROOT}/agent-tests"
GUIDE_PATH="${1:-${AGENT_TESTS_DIR}/guides/lif_snntorch.md}"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   NMTK Notebook Reproduction Agent                  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "▶ Guide: ${GUIDE_PATH}"
echo "▶ The agent will automatically bring the neuro_toolkit app"
echo "  to the foreground. You do NOT need to switch windows."
echo ""

if [ ! -f "${GUIDE_PATH}" ]; then
    echo "❌ Guide file not found: ${GUIDE_PATH}"
    echo "   Pass a guide path, e.g.: ./agent-tests/run_agent.sh agent-tests/guides/lif_snntorch.md"
    exit 1
fi

# ── 0. Fast AppleEvent preflight ─────────────────────────────────────────────
# Fail in ~1-20s if System Events can't reach neuro_toolkit, instead of
# discovering this ~90s in, after Ollama/OmniParser/paddle models have loaded.
echo "► Checking System Events can reach neuro_toolkit…"
if ! osascript \
    -e 'with timeout of 20 seconds' \
    -e 'tell application "System Events" to get name of first process whose name is "neuro_toolkit"' \
    -e 'end timeout' > /dev/null 2>&1; then
    echo ""
    echo "❌ Could not reach neuro_toolkit via System Events (AppleEvent failed/timed out)."
    echo "   Fixes to try:"
    echo "   1. Make sure neuro_toolkit.app is actually running."
    echo "   2. Run this script from an actual Terminal.app (or iTerm) window —"
    echo "      NOT from inside an agent/CLI shell (e.g. Claude Code) — AppleEvents"
    echo "      need Accessibility permission bound to a real windowed terminal app."
    echo "   3. Grant: System Settings → Privacy & Security → Accessibility   → Terminal ✓"
    echo "             System Settings → Privacy & Security → Screen Recording → Terminal ✓"
    echo "   4. Re-run this script after granting permissions (may require restarting Terminal)."
    echo ""
    exit 1
fi
echo "  ✅ neuro_toolkit is reachable."

# ── 1. Ollama on designated port ─────────────────────────────────────────────
export OLLAMA_HOST=127.0.0.1:11435
export HF_HUB_DISABLE_PROGRESS_BARS=1
export PYTHONDONTWRITEBYTECODE=1   # Prevent stale .pyc issues

echo "► Checking Ollama server..."
if ! curl -sf http://${OLLAMA_HOST}/api/tags > /dev/null 2>&1; then
    echo "  Starting Ollama on ${OLLAMA_HOST}..."
    OLLAMA_HOST=${OLLAMA_HOST} /opt/homebrew/bin/ollama serve > /tmp/ollama_agent.log 2>&1 &
    echo "  Waiting for Ollama to be ready..."
    for i in $(seq 1 20); do
        sleep 2
        if curl -sf http://${OLLAMA_HOST}/api/tags > /dev/null 2>&1; then
            echo "  ✅ Ollama ready."
            break
        fi
        echo "  ... still waiting ($((i*2))s)"
    done
else
    echo "  ✅ Ollama already running."
fi

# Show available models
echo "  Available models:"
curl -sf http://${OLLAMA_HOST}/api/tags | python3 -c \
    "import json,sys; [print('    -', m['name']) for m in json.load(sys.stdin)['models']]" \
    2>/dev/null || echo "    (could not list)"

# ── 2. macOS permissions reminder ───────────────────────────────────────────
echo ""
echo "► Checking macOS permissions..."
echo "  If the agent cannot click/screenshot, grant:"
echo "  System Settings → Privacy & Security → Accessibility   → Terminal ✓"
echo "  System Settings → Privacy & Security → Screen Recording → Terminal ✓"
echo ""

# ── 3. Launch agent ──────────────────────────────────────────────────────────
echo "► Starting agent in 3 seconds (keep neuro_toolkit running)..."
sleep 3

cd "${AGENT_TESTS_DIR}"
OLLAMA_HOST=${OLLAMA_HOST} conda run --no-capture-output -n omni python local_host_agent.py "${GUIDE_PATH}"

echo ""
echo "✅ Agent run finished. Check agent-tests/reports/ for the report."
```

- [ ] **Step 3: Manual verification**

From an actual Terminal.app window (not this session):
```bash
chmod +x agent-tests/run_agent.sh
./agent-tests/run_agent.sh
```
Expected: preflight prints `✅ neuro_toolkit is reachable.` within a few seconds (no AppleEvent timeout), then proceeds to the Ollama check and launches the agent with `guides/lif_snntorch.md`. If Accessibility isn't granted to Terminal, expected: the actionable `❌ Could not reach neuro_toolkit...` message and immediate exit, not a 90-second wait.

- [ ] **Step 4: Commit**

```bash
cd $HOME/NeuroMorphicToolKit
git add agent-tests/run_agent.sh
git commit -m "feat: guide-path argument + fast AppleEvent preflight in run_agent.sh"
```

---

## Self-Review Notes

- **Spec coverage:** Task 1 → guide relocation; Task 2 → vision payload + model swap; Task 3 → drop scripted macro, guide-driven `main()`; Task 4 → wire screenshot into the call site; Task 5 → AppleScript timeout/retry; Task 6 → shell preflight + guide arg. All six spec bullets covered.
- **Placeholder scan:** none — every step has literal file content or code.
- **Type consistency:** `load_guide(path: str) -> str` used identically in Tasks 1 and 3; `query_llm(instruction, element_summary, history, img)` signature matches across Tasks 2 and 4; `main(guide_path: str)` matches across Tasks 3, 4, and 6's shell invocation (`sys.argv[1]`).
