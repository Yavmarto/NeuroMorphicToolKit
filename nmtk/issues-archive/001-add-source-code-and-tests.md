# Add Python Source Code and Tests to nmtk

**Priority:** High  
**Type:** Code Quality / Testing  
**Date:** 2026-03-19  

## Description

The `nmtk` submodule currently contains **no Python source code** — only documentation files (`docs/conf.py`) and issue archives. It appears to be a meta-package or documentation-only module. If this is intended to be a Python package, it needs source code and tests. If it's docs-only, it should be restructured accordingly.

## Tasks

- [ ] Clarify purpose: is this a Python package or docs-only?
- [ ] If Python package: add `__init__.py`, `pyproject.toml`, and test files
- [ ] If docs-only: remove from the Python submodule list in CODING_STYLE_GUIDE.md
- [ ] Add `CODING_STYLE_GUIDE.md` if it will contain code
