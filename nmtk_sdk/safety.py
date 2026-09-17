from __future__ import annotations

import ast

DANGEROUS_MODULES: frozenset[str] = frozenset({
    "os", "subprocess", "socket", "sys", "shutil", "pathlib",
    "importlib", "ctypes", "pickle", "shelve", "builtins",
    "runpy", "code", "codeop", "compileall", "py_compile",
    "marshal",
})


def scan_imports(source: str) -> list[str]:
    """Parse source with ast and return list of dangerous top-level module names found.
    Returns empty list on syntax errors (advisory only — caller decides what to do).
    """
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return []

    found: list[str] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                root = alias.name.split(".")[0]
                if root in DANGEROUS_MODULES:
                    found.append(root)
        elif isinstance(node, ast.ImportFrom) and node.module:
            root = node.module.split(".")[0]
            if root in DANGEROUS_MODULES:
                found.append(root)
    return found
