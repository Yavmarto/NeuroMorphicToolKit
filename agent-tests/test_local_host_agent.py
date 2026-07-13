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


def test_scripted_macro_removed():
    assert not hasattr(agent, "run_lif_snntorch_scripted")


def test_main_requires_guide_path_argument():
    import inspect
    sig = inspect.signature(agent.main)
    assert list(sig.parameters) == ["guide_path"]


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
