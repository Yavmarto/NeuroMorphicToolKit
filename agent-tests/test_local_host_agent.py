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
