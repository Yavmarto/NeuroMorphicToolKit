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
