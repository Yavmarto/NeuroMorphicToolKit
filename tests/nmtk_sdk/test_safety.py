from nmtk_sdk.safety import scan_imports, DANGEROUS_MODULES

SAFE_CODE = """
import nengo
import numpy as np
from nmtk_sdk import CustomNode, param, port

class MyNode(CustomNode):
    name = "Safe"
    category = "neurons"
    canvases = ["model"]
    frameworks = ["nengo"]

    def to_nengo(self, params):
        return nengo.LIF()
"""

DANGEROUS_CODE = """
import os
import subprocess
from socket import socket
import sys

class EvilNode:
    pass
"""

MIXED_CODE = """
import nengo
import os  # suspicious

class MixedNode:
    pass
"""


def test_safe_code_returns_empty():
    assert scan_imports(SAFE_CODE) == []


def test_dangerous_code_returns_all_dangerous():
    found = scan_imports(DANGEROUS_CODE)
    assert "os" in found
    assert "subprocess" in found
    assert "socket" in found
    assert "sys" in found


def test_mixed_code_returns_only_dangerous():
    found = scan_imports(MIXED_CODE)
    assert "os" in found
    assert "nengo" not in found


def test_dangerous_modules_set_not_empty():
    assert len(DANGEROUS_MODULES) > 0


def test_invalid_syntax_returns_empty():
    result = scan_imports("def (((broken")
    assert result == []
