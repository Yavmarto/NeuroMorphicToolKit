import os
import sys
import time
import json
import re
import base64
import io
import requests
import pyautogui
import mss
from PIL import Image
from datetime import datetime
from pathlib import Path

# Ensure we can import OmniParser utils
sys.path.append(os.path.expanduser("~/OmniParser"))
from util.utils import check_ocr_box, get_yolo_model, get_caption_model_processor, get_som_labeled_img
import torch

# ── Config ────────────────────────────────────────────────────────────────────
OLLAMA_URL   = "http://127.0.0.1:11435/api/chat"
OLLAMA_MODEL = "qwen3.5:35b"         # vision-capable — sees the screenshot, not just the element list
MAX_ELEMENTS = 80                    # cap to avoid context overflow
STEPS        = 30
SCREENSHOT_DIR = Path(__file__).parent / "screenshots"
REPORT_DIR     = Path(__file__).parent / "reports"
SCREENSHOT_DIR.mkdir(parents=True, exist_ok=True)
REPORT_DIR.mkdir(parents=True, exist_ok=True)


# Numbered checklist for paper/01_lif/lif_snntorch.ipynb. Earlier version was
# copied verbatim from `current tasks/16 june/cnlstudio_notebook_analysis.md`'s
# "UI Replication Guide", which turned out to describe UI that doesn't exist in
# this build (e.g. there is no "Export/File Menu"). Rewritten below to name the
# ACTUAL widgets (tooltip/label text confirmed by reading the Flutter source:
# neurocnl/frontend/lib/widgets/nir_importer_tab.dart,
# neurocnl/frontend/lib/screens/canvas/canvas_screen.dart,
# neurocnl/frontend/lib/models/canvas/pipeline_dag.dart) so a small model has an
# actual click target for every step instead of an abstract goal.
NIR_FILE_PATH = "/Users/yoshimartodihardjo/NeuroMorphicToolKit/paper/01_lif/lif_norse.nir"
TASK_INSTRUCTION = (
    "You are reproducing the 'lif_snntorch.ipynb' notebook inside the NeuroStudio (neuro_toolkit) "
    "application by following this EXACT numbered checklist, in order. Use the action history below "
    "to figure out which steps you've already completed, then perform the next uncompleted one. "
    "Do not skip ahead and do not repeat a step that already succeeded.\n\n"
    "Canvas: Model\n"
    "1. Navigate to the Model Canvas (stepper tab '2. Model').\n"
    "2. Click the icon whose tooltip/content is 'NIR Importer' to open its side panel.\n"
    "3. Inside that panel, click the button labeled 'Load .nir'.\n"
    f"4. A native file picker will open as a SEPARATE window you cannot see or click into — do not try. "
    f"Instead: press key 'cmd+shift+g', then type the exact text '{NIR_FILE_PATH}', then press key "
    "'Return', then press key 'Return' again to confirm the file selection.\n"
    "5. Wait a couple of seconds, then confirm the Model canvas now shows a real graph (no longer empty).\n\n"
    "Canvas: Eval\n"
    "6. Navigate to the Eval Canvas (stepper tab '4. Eval').\n"
    "7. Click the '+' icon in the bottom toolbar (tooltip 'Add') to open the 'Add Node' picker.\n"
    "8. Click the tile labeled 'Spike Generator'. Configure it: n_neurons=1, n_timesteps=100, "
    "pattern=isi_regular, isi_period=10, seed=42.\n"
    "9. Click the '+' icon again, then click the tile labeled 'State Reset'.\n"
    "10. Click the '+' icon again, then click the tile labeled 'Forward Pass'. Set its eval_mode = true.\n"
    "11. Click the '+' icon again, then click the tile labeled 'Spike Rate Logger'.\n"
    "12. Drag from the Spike Generator node's output port to the Forward Pass node's input port "
    "(use the 'drag' action with from_id/to_id set to those two ports' element IDs).\n"
    "13. Drag from the State Reset node's model-output port to the Forward Pass node's model-input port.\n"
    "14. Drag from the Forward Pass node's spikes-output port to the Spike Rate Logger node's spikes-input port. "
    "Leave any other Forward Pass outputs (membrane, model) unconnected.\n"
    "15. Click 'Run Eval'.\n\n"
    "Results Step: Dynamics Tab\n"
    "16. After the eval run completes, navigate to the Results step and open the Dynamics tab.\n"
    "17. Confirm the Spike Raster panel shows the output spike times.\n"
    "18. Confirm the Membrane Voltage Trace panel shows the LIF membrane potential over 100 timesteps.\n"
    "19. Export results to CSV via the export button.\n"
)

# ── Helpers ───────────────────────────────────────────────────────────────────
import subprocess

def get_window_rect_points():
    """Return (x, y, w, h) in points for neuro_toolkit's front window, or None
    if it can't be determined (e.g. Accessibility permission not granted)."""
    try:
        result = subprocess.run(
            ['osascript', '-e',
             'tell application "System Events" to tell process "neuro_toolkit" '
             'to get {position, size} of front window'],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            return None
        nums = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", result.stdout)]
        if len(nums) != 4:
            return None
        x, y, w, h = nums
        return x, y, w, h
    except Exception:
        return None


def get_screenshot():
    # Force the app to the foreground before every screenshot.
    # NOTE: do NOT send "reopen" here — that Apple Event is for restoring a
    # window when the app has none visible, and Flutter's macOS embedder
    # mishandles it even when a window is already open, knocking it out of
    # view and leaving only the menu bar for OmniParser to see.
    subprocess.run(['osascript', '-e', 'tell application "neuro_toolkit" to activate', '-e', 'tell application "System Events" to set frontmost of process "neuro_toolkit" to true'])
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


def save_screenshot(img: Image.Image, step: int, label: str = "") -> str:
    ts = datetime.now().strftime("%H%M%S")
    fname = SCREENSHOT_DIR / f"step{step:02d}_{ts}_{label}.png"
    img.save(str(fname))
    return str(fname)


def build_element_summary(parsed_content_list: list, max_items: int = MAX_ELEMENTS) -> str:
    """
    Build a compact element list for the LLM.
    Prefer interactable (icon/button) elements; truncate at max_items.
    Format: ID | type | content
    """
    # Attach original index to each element
    for i, elem in enumerate(parsed_content_list):
        elem["original_id"] = str(i)
        
    interactable = [e for e in parsed_content_list if e.get("interactivity")]
    text_only    = [e for e in parsed_content_list if not e.get("interactivity")]

    # Fill up to MAX_ELEMENTS: interactable first, then text
    combined = (interactable + text_only)[:max_items]

    lines = []
    for elem in combined:
        content = elem.get("content") or ""
        etype   = elem.get("type", "?")
        orig_id = elem["original_id"]
        lines.append(f"{orig_id}\t{etype}\t{content[:80]}")
    return "\n".join(lines)


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
            {"role": "user",   "content": user_prompt, "images": [encoded_img]},
        ],
        "format": "json",
        "stream": False,
        "options": {"temperature": 0.1, "num_ctx": 8192},
    }

    try:
        resp = requests.post(OLLAMA_URL, json=payload, timeout=120)
        resp.raise_for_status()
        raw = resp.json()["message"]["content"]
        # Strip any accidental markdown fences
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


def element_center_px(target_id: str, label_coordinates: dict, screen_w: int, screen_h: int):
    if target_id not in label_coordinates:
        return None, None
    x_r, y_r, w_r, h_r = label_coordinates[target_id]
    cx_r = x_r + (w_r / 2)
    cy_r = y_r + (h_r / 2)
    return int(cx_r * screen_w), int(cy_r * screen_h)


# ── Scripted routine ─────────────────────────────────────────────────────────
# The stepper tabs and toolbar icon positions are identical in every screenshot
# we've captured so far — there's nothing for a vision model to "discover" there.
# Only the "Add Node" popup's tile layout is actually unknown, so that's the only
# place we still call OmniParser. Ratios measured from
# agent-tests/screenshots/step16_232409_before.png (1512x874 window crop).
MODEL_TAB = (0.1217, 0.0835)
EVAL_TAB = (0.2725, 0.0835)
NIR_IMPORTER_ICON = (0.6027, 0.9531)   # rightmost icon, Model canvas toolbar
EVAL_ADD_ICON = (0.5311, 0.9531)       # "+" icon, Eval canvas toolbar


def click_ratio(win_w, win_h, win_origin, rx, ry, label=""):
    x = int(win_origin[0] + rx * win_w)
    y = int(win_origin[1] + ry * win_h)
    print(f"  [scripted] Clicking {label} at ({x}, {y})")
    pyautogui.moveTo(x, y, duration=0.3)
    pyautogui.click()
    time.sleep(1.2)


def parse_screen(img, yolo_model, caption_model_processor):
    """Full OmniParser pass (OCR + icon detect + caption) — slow (~60-90s).
    Only call this where the layout is genuinely unknown."""
    ocr_result, _ = check_ocr_box(
        img, display_img=False, output_bb_format="xyxy",
        easyocr_args={"paragraph": False, "text_threshold": 0.9},
        use_paddleocr=False,
    )
    text, ocr_bbox = ocr_result
    _, label_coordinates, parsed_content_list = get_som_labeled_img(
        img, yolo_model,
        BOX_TRESHOLD=0.3,
        output_coord_in_ratio=True,
        ocr_bbox=ocr_bbox,
        caption_model_processor=caption_model_processor,
        ocr_text=text,
        iou_threshold=0.1,
        imgsz=640,
    )
    for i, elem in enumerate(parsed_content_list):
        elem["original_id"] = str(i)
    return label_coordinates, parsed_content_list


def find_element_by_text(parsed_content_list, needle):
    needle_l = needle.lower()
    for elem in parsed_content_list:
        content = (elem.get("content") or "").lower()
        if needle_l in content:
            return elem["original_id"]
    return None


def click_element(label_coordinates, parsed_content_list, target_id, win_w, win_h, win_origin, label=""):
    cx, cy = element_center_px(target_id, label_coordinates, win_w, win_h)
    if cx is None:
        print(f"  ⚠️  Could not resolve element {target_id} for \"{label}\"")
        return False
    abs_x, abs_y = int(win_origin[0] + cx), int(win_origin[1] + cy)
    print(f"  [scripted] Clicking found element {target_id} (\"{label}\") at ({abs_x}, {abs_y})")
    pyautogui.moveTo(abs_x, abs_y, duration=0.3)
    pyautogui.click()
    time.sleep(1.2)
    return True


def run_lif_snntorch_scripted():
    """Deterministic macro for paper/01_lif/lif_snntorch.ipynb: script every
    fixed, already-confirmed click directly, and only fall back to OmniParser
    text-matching (no LLM call — OCR/caption content is searched directly) for
    the one part whose layout isn't fixed: the 'Add Node' popup's tiles."""
    print("Loading OmniParser models...")
    yolo_model = get_yolo_model(model_path=os.path.expanduser("~/OmniParser/weights/icon_detect/model.pt"))
    caption_model_processor = get_caption_model_processor(
        model_name="florence2",
        model_name_or_path=os.path.expanduser("~/OmniParser/weights/icon_caption_florence"),
    )

    print("Agent starting in 5 seconds — make neuro_toolkit the active window…")
    time.sleep(5)

    # 1. Model canvas
    _, win_w, win_h, win_origin = get_screenshot()
    click_ratio(win_w, win_h, win_origin, *MODEL_TAB, "Model tab")

    # 2. Open NIR Importer panel
    _, win_w, win_h, win_origin = get_screenshot()
    click_ratio(win_w, win_h, win_origin, *NIR_IMPORTER_ICON, "NIR Importer icon")

    # 3. Find + click "Load .nir" inside the panel (position not previously
    # confirmed — one live OmniParser lookup, since this needs real detection).
    img, win_w, win_h, win_origin = get_screenshot()
    label_coords, parsed = parse_screen(img, yolo_model, caption_model_processor)
    load_nir_id = find_element_by_text(parsed, "load .nir") or find_element_by_text(parsed, "load")
    if load_nir_id is None:
        print("  ⚠️  Could not find 'Load .nir' button — check the latest step*_before.png "
              "for the panel layout and adjust NIR_IMPORTER_ICON/search text.")
        return
    click_element(label_coords, parsed, load_nir_id, win_w, win_h, win_origin, "Load .nir")

    # 4. Native file picker is a separate OS window we can't see — go in blind.
    time.sleep(1.5)
    pyautogui.hotkey('command', 'shift', 'g')
    time.sleep(0.8)
    pyautogui.typewrite(NIR_FILE_PATH, interval=0.02)
    pyautogui.press('return')
    time.sleep(0.8)
    pyautogui.press('return')
    time.sleep(2)

    # 5. Eval canvas
    _, win_w, win_h, win_origin = get_screenshot()
    click_ratio(win_w, win_h, win_origin, *EVAL_TAB, "Eval tab")

    # 6-8. Add each pipeline node via the "+" -> "Add Node" popup, found by
    # direct text match against the popup's own labels (no LLM guessing).
    for name in ("Spike Generator", "State Reset", "Forward Pass", "Spike Rate Logger"):
        _, win_w, win_h, win_origin = get_screenshot()
        click_ratio(win_w, win_h, win_origin, *EVAL_ADD_ICON, "+ (Add Node)")

        img, win_w, win_h, win_origin = get_screenshot()
        label_coords, parsed = parse_screen(img, yolo_model, caption_model_processor)
        tile_id = find_element_by_text(parsed, name)
        if tile_id is None:
            print(f"  ⚠️  Could not find node tile '{name}' in the Add Node popup — "
                  f"check the latest step*_before.png.")
            continue
        click_element(label_coords, parsed, tile_id, win_w, win_h, win_origin, name)

    final_img, _, _, _ = get_screenshot()
    save_screenshot(final_img, 99, "nodes_added")
    print("\nAll 4 nodes attempted. Check agent-tests/screenshots/step99_*_nodes_added.png "
          "to confirm they landed on the Eval canvas before wiring ports / Run Eval — "
          "that part isn't scripted yet since we haven't seen the populated canvas.")


# ── Main loop (general LLM-driven agent, kept for other notebooks) ──────────
def main():
    report_lines = [
        f"# Notebook Reproduction Report",
        f"Generated: {datetime.now().isoformat()}",
        "",
        f"## Task",
        TASK_INSTRUCTION,
        "",
        "## Steps",
    ]

    print("Loading OmniParser models...")
    yolo_model = get_yolo_model(
        model_path=os.path.expanduser("~/OmniParser/weights/icon_detect/model.pt")
    )
    caption_model_processor = get_caption_model_processor(
        model_name="florence2",
        model_name_or_path=os.path.expanduser("~/OmniParser/weights/icon_caption_florence"),
    )

    print(f"Agent starting in 5 seconds — make CNLStudio the active window…")
    time.sleep(5)

    history = []
    prev_element_summary = None

    for step in range(1, STEPS + 1):
        print(f"\n{'='*60}\n--- Step {step}/{STEPS} ---")

        # 1. Screenshot — cropped to the app window; win_w/win_h are that
        # window's own point-space size, win_origin is its (x, y) on screen.
        img, win_w, win_h, win_origin = get_screenshot()
        shot_path = save_screenshot(img, step, "before")

        # 2. Parse screen
        print("  Parsing screen with OmniParser…")
        try:
            ocr_result, _ = check_ocr_box(
                img, display_img=False, output_bb_format="xyxy",
                easyocr_args={"paragraph": False, "text_threshold": 0.9},
                use_paddleocr=False,
            )
            text, ocr_bbox = ocr_result

            _, label_coordinates, parsed_content_list = get_som_labeled_img(
                img, yolo_model,
                BOX_TRESHOLD=0.05,
                output_coord_in_ratio=True,
                ocr_bbox=ocr_bbox,
                caption_model_processor=caption_model_processor,
                ocr_text=text,
                iou_threshold=0.1,
                imgsz=640,
            )
        except Exception as e:
            print(f"  [OmniParser error] {e}")
            report_lines.append(f"- **Step {step}**: OmniParser error — {e}")
            time.sleep(2)
            continue

        print(f"  Detected {len(parsed_content_list)} elements.")
        element_summary = build_element_summary(parsed_content_list)
        content_by_id = {e["original_id"]: (e.get("content") or e.get("type", "?")) for e in parsed_content_list}

        # Now that we can see the result of the PREVIOUS action, record whether
        # it actually changed anything — without this, a static-target click
        # (e.g. a non-interactive label) repeats forever at low temperature.
        if history:
            effect = "no visible effect (screen unchanged)" if element_summary == prev_element_summary else "screen changed"
            history[-1] += f" -> {effect}"
        prev_element_summary = element_summary

        # 3. Ask LLM
        print("  Querying LLM…")
        action_obj = query_llm(TASK_INSTRUCTION, element_summary, history)
        print(f"  LLM → {action_obj}")
        history.append(f"Step {step}: {json.dumps(action_obj)}")

        action = action_obj.get("action", "error")
        report_lines.append(f"- **Step {step}**: `{action}` — {json.dumps(action_obj)}")
        report_lines.append(f"  Screenshot: `{shot_path}`")

        # 4. Execute action
        if action == "done":
            print("  ✅ Task complete!")
            report_lines.append("\n## Result\n✅ Agent reported task complete.")
            break

        elif action == "click":
            target_id = str(action_obj.get("target_id", ""))
            # label_coordinates keys are stringified phrase indices; ratios are
            # relative to the cropped window image, so scale by win_w/win_h and
            # add the window's screen origin to get an absolute click point.
            cx, cy = element_center_px(target_id, label_coordinates, win_w, win_h)
            if cx is not None:
                abs_x, abs_y = int(win_origin[0] + cx), int(win_origin[1] + cy)
                label = content_by_id.get(target_id, "?")
                print(f"  Clicking element {target_id} (\"{label}\") at ({abs_x}, {abs_y})")
                pyautogui.moveTo(abs_x, abs_y, duration=0.4)
                pyautogui.click()
                time.sleep(1.5)
            else:
                print(f"  ⚠️  Element ID '{target_id}' not found — attempting coordinate fallback")
                # Some models return raw coordinates, relative to the window
                coords = action_obj.get("coordinates")
                if coords and len(coords) == 2:
                    fx = min(max(int(coords[0]), 0), int(win_w) - 1)
                    fy = min(max(int(coords[1]), 0), int(win_h) - 1)
                    pyautogui.moveTo(int(win_origin[0] + fx), int(win_origin[1] + fy), duration=0.4)
                    pyautogui.click()
                    time.sleep(1.5)
                else:
                    print("  No valid coordinates available, skipping.")
            time.sleep(1)

        elif action == "drag":
            from_id = str(action_obj.get("from_id", ""))
            to_id = str(action_obj.get("to_id", ""))
            fx, fy = element_center_px(from_id, label_coordinates, win_w, win_h)
            tx, ty = element_center_px(to_id, label_coordinates, win_w, win_h)
            if fx is not None and tx is not None:
                abs_fx, abs_fy = int(win_origin[0] + fx), int(win_origin[1] + fy)
                abs_tx, abs_ty = int(win_origin[0] + tx), int(win_origin[1] + ty)
                print(f"  Dragging element {from_id} (\"{content_by_id.get(from_id, '?')}\") "
                      f"-> element {to_id} (\"{content_by_id.get(to_id, '?')}\") "
                      f"[({abs_fx}, {abs_fy}) -> ({abs_tx}, {abs_ty})]")
                pyautogui.moveTo(abs_fx, abs_fy, duration=0.3)
                pyautogui.mouseDown()
                pyautogui.moveTo(abs_tx, abs_ty, duration=0.5)
                pyautogui.mouseUp()
                time.sleep(1.5)
            else:
                print(f"  ⚠️  Drag endpoint not found (from_id={from_id!r}, to_id={to_id!r}), skipping.")
            time.sleep(1)

        elif action == "type":
            text_to_type = action_obj.get("text", "")
            print(f"  Typing: {repr(text_to_type)}")
            pyautogui.typewrite(text_to_type, interval=0.05)
            time.sleep(0.5)

        elif action == "key":
            key_combo = action_obj.get("text", "")
            print(f"  Key: {key_combo}")
            # pyautogui uses '+' separator, e.g. 'shift+Return'
            keys = [k.strip() for k in key_combo.replace("+", " ").split()]
            pyautogui.hotkey(*keys)
            time.sleep(1)

        elif action == "scroll":
            direction = action_obj.get("direction", "down")
            amount    = int(action_obj.get("amount", 3))
            clicks = amount if direction == "down" else -amount
            print(f"  Scrolling {direction} by {amount}")
            pyautogui.scroll(clicks)
            time.sleep(0.5)

        elif action == "wait":
            reason = action_obj.get("reason", "")
            print(f"  Waiting 3s — {reason}")
            time.sleep(3)

        else:
            print(f"  Unknown/error action: {action}")
            time.sleep(2)

        # Diagnostic: capture what the screen looks like right after an action
        # that's supposed to change something, so before/after pairs show
        # directly whether the click/type/key actually registered with the app.
        if action in ("click", "type", "key", "drag"):
            img_after, _, _, _ = get_screenshot()
            after_path = save_screenshot(img_after, step, "after")
            report_lines.append(f"  Screenshot after: `{after_path}`")

    else:
        report_lines.append("\n## Result\n⚠️ Reached maximum steps without completing task.")

    # Write report
    report_path = REPORT_DIR / f"report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.md"
    report_path.write_text("\n".join(report_lines))
    print(f"\n📄 Report saved to: {report_path}")


if __name__ == "__main__":
    # Default: the fast scripted macro for lif_snntorch (no per-step LLM calls
    # for the fixed navigation). Pass --llm to use the general vision-LLM loop
    # instead (needed for a different notebook, or if the UI layout changes).
    if "--llm" in sys.argv:
        main()
    else:
        run_lif_snntorch_scripted()
