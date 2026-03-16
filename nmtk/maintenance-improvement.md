# Maintenance & Development Automation Improvement Plan

## Executive Summary

While the CI pipeline covers linting (ruff), type checking (mypy), and testing (pytest, flutter test) with coverage collection, several maintenance automation gaps remain. This spec addresses: dependency management, security scanning, pre-commit hooks, documentation generation, changelog automation, version management, Docker CI verification, and Arduino CI.

---

## Current State

### What's Already Automated ✅

| Category | Tool | Scope | Status |
|----------|------|-------|--------|
| **Python linting** | ruff check + ruff format | neurocnl + NDH | ✅ Enforced in CI |
| **Python type checking** | mypy | neurocnl + NDH | ✅ Enforced in CI |
| **Python unit tests** | pytest | neurocnl + NDH | ✅ CI on push/PR |
| **Python integration tests** | pytest (MuJoCo) | NDH only | ✅ Separate CI workflow |
| **Flutter analysis** | flutter analyze | neurocnl frontend | ✅ Enforced in CI |
| **Flutter tests** | flutter test | neurocnl frontend | ✅ CI on push/PR |
| **Flutter web build** | flutter build web | neurocnl frontend | ✅ Verified in CI |
| **Coverage collection** | pytest-cov + flutter --coverage | All | ✅ Artifacts uploaded |

### What's Not Automated ❌

| Category | Gap | Impact |
|----------|-----|--------|
| **Dependency updates** | No Dependabot/Renovate | Stale deps, missed security patches |
| **Security scanning** | No pip-audit / safety / Trivy | Vulnerable dependencies undetected |
| **Pre-commit hooks** | No local enforcement | CI catches issues late, slow feedback |
| **Coverage reporting** | Artifacts only, no dashboard | Can't track coverage trends over time |
| **Changelog** | Manual, no automation | Inconsistent release notes |
| **Version management** | Hard-coded in pyproject.toml/pubspec.yaml | Manual bumping, easy to forget |
| **Documentation** | Manual READMEs only | No API docs, no generated site |
| **Docker verification** | Compose exists but not tested in CI | Broken Docker builds undetected |
| **Arduino CI** | servo_control has zero CI | Compilation errors undetected |
| **Branch protection** | Unknown if configured | Direct pushes could bypass CI |

---

## Implementation Plan

### 1. Dependabot Configuration

**Priority: HIGH**
**Effort: Small (single config file)**

Create `.github/dependabot.yml` at the root workspace level:

```yaml
version: 2
updates:
  # Python - neurocnl
  - package-ecosystem: "pip"
    directory: "/neurocnl"
    schedule:
      interval: "weekly"
      day: "monday"
    open-pull-requests-limit: 10
    labels: ["dependencies", "python"]
    reviewers: ["yoshimartodihardjo"]
    groups:
      python-minor:
        update-types: ["minor", "patch"]

  # Python - Neuro-Dream-Hand
  - package-ecosystem: "pip"
    directory: "/Neuro-Dream-Hand"
    schedule:
      interval: "weekly"
      day: "monday"
    open-pull-requests-limit: 10
    labels: ["dependencies", "python"]
    groups:
      python-minor:
        update-types: ["minor", "patch"]

  # Flutter/Dart - neurocnl frontend
  - package-ecosystem: "pub"
    directory: "/neurocnl/frontend"
    schedule:
      interval: "weekly"
      day: "monday"
    open-pull-requests-limit: 5
    labels: ["dependencies", "flutter"]

  # GitHub Actions
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    labels: ["dependencies", "ci"]

  # Docker
  - package-ecosystem: "docker"
    directory: "/neurocnl/backend"
    schedule:
      interval: "monthly"
    labels: ["dependencies", "docker"]

  - package-ecosystem: "docker"
    directory: "/neurocnl/frontend"
    schedule:
      interval: "monthly"
    labels: ["dependencies", "docker"]
```

**What this gives you:**
- Weekly PRs for outdated Python/Dart/Action deps
- Grouped minor/patch updates (fewer PRs)
- Auto-labeled for easy filtering
- CI runs on Dependabot PRs to validate updates

---

### 2. Security Scanning

**Priority: HIGH**
**Effort: Small**

#### 2.1 — Python Dependency Audit

Add to existing `python_ci.yml`:

```yaml
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - run: pip install pip-audit
      - name: Audit neurocnl
        run: pip-audit -r neurocnl/backend/requirements.txt
      - name: Audit Neuro-Dream-Hand
        run: pip-audit -r Neuro-Dream-Hand/requirements.txt
```

#### 2.2 — Docker Image Scanning

Add Trivy scan after Docker builds:

```yaml
  - name: Scan Docker image
    uses: aquasecurity/trivy-action@master
    with:
      image-ref: ghcr.io/yoshimartodihardjo/neurocnl-server:latest
      format: 'sarif'
      output: 'trivy-results.sarif'
  - name: Upload Trivy results
    uses: github/codeql-action/upload-sarif@v3
    with:
      sarif_file: 'trivy-results.sarif'
```

#### 2.3 — GitHub Code Scanning (CodeQL)

```yaml
# .github/workflows/codeql.yml
name: CodeQL Analysis
on:
  push:
    branches: [main]
  schedule:
    - cron: '0 6 * * 1'  # Weekly Monday 6am
jobs:
  analyze:
    runs-on: ubuntu-latest
    permissions:
      security-events: write
    strategy:
      matrix:
        language: [python, javascript]
    steps:
      - uses: actions/checkout@v4
      - uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
      - uses: github/codeql-action/analyze@v3
```

---

### 3. Pre-commit Hooks

**Priority: MEDIUM**
**Effort: Small**

Create `.pre-commit-config.yaml` at workspace root:

```yaml
repos:
  # General
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
      - id: check-toml
      - id: check-merge-conflict
      - id: check-added-large-files
        args: ['--maxkb=1000']
      - id: detect-private-key

  # Python - ruff (lint + format)
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.3.0
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format

  # Python - mypy
  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.8.0
    hooks:
      - id: mypy
        additional_dependencies: [types-all]
        args: [--config-file=neurocnl/pyproject.toml]

  # Markdown
  - repo: https://github.com/igorshubovych/markdownlint-cli
    rev: v0.39.0
    hooks:
      - id: markdownlint
        args: [--fix, --disable, MD013, MD033, MD041]

  # Secrets detection
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
```

**Developer setup:**
```bash
pip install pre-commit
pre-commit install
# Optional: run on all files
pre-commit run --all-files
```

**Add to contributing docs** and onboarding instructions.

---

### 4. Coverage Reporting (Codecov)

**Priority: MEDIUM**
**Effort: Small**

Replace artifact uploads with Codecov:

```yaml
  # In python_ci.yml after pytest
  - name: Upload coverage to Codecov
    uses: codecov/codecov-action@v4
    with:
      token: ${{ secrets.CODECOV_TOKEN }}
      files: coverage.xml
      flags: neurocnl
      fail_ci_if_error: false

  # In flutter_ci.yml after flutter test
  - name: Upload Flutter coverage
    uses: codecov/codecov-action@v4
    with:
      token: ${{ secrets.CODECOV_TOKEN }}
      files: neurocnl/frontend/coverage/lcov.info
      flags: flutter
```

**Setup required:**
1. Sign up at codecov.io with GitHub OAuth
2. Add `CODECOV_TOKEN` to repo secrets
3. Create `codecov.yml` for thresholds:

```yaml
# codecov.yml
coverage:
  status:
    project:
      default:
        target: 60%
        threshold: 5%
    patch:
      default:
        target: 70%
comment:
  layout: "diff, flags, components"
  behavior: default
flags:
  neurocnl:
    paths: ["neurocnl/"]
  ndh:
    paths: ["Neuro-Dream-Hand/"]
  flutter:
    paths: ["neurocnl/frontend/"]
```

**What this gives you:**
- Coverage trend dashboard
- PR comments showing coverage diff
- Coverage badges for README
- Fail CI if coverage drops below threshold

---

### 5. Automated Changelog

**Priority: MEDIUM**
**Effort: Small**

#### 5.1 — Adopt Conventional Commits

Enforce commit message format: `type(scope): description`

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`

```
feat(backend): add prosthetic simulation endpoints
fix(frontend): resolve connection timeout on slow networks
ci: add multi-platform release builds
docs: update installation guide for Docker
```

#### 5.2 — Commitlint in CI

```yaml
# .github/workflows/commitlint.yml
name: Lint Commits
on: [pull_request]
jobs:
  commitlint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: wagoid/commitlint-github-action@v5
        with:
          configFile: .commitlintrc.yml
```

```yaml
# .commitlintrc.yml
extends: ['@commitlint/config-conventional']
rules:
  scope-enum: [2, always, [backend, frontend, ndh, neurocnl, servo, ci, docs]]
```

#### 5.3 — Auto-generate Changelog on Release

```yaml
# In release workflow
  - name: Generate changelog
    uses: orhun/git-cliff-action@v3
    with:
      config: cliff.toml
      args: --latest --strip header
    env:
      OUTPUT: CHANGELOG.md
```

---

### 6. Version Management

**Priority: LOW**
**Effort: Small**

Use `python-semantic-release` for automated version bumping:

```yaml
# .github/workflows/release.yml (addition)
  version-bump:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - run: pip install python-semantic-release
      - run: semantic-release version
      - run: semantic-release publish
```

```toml
# pyproject.toml addition
[tool.semantic_release]
version_toml = ["pyproject.toml:project.version"]
branch = "main"
commit_message = "chore(release): v{version}"
build_command = "pip install build && python -m build"
```

**What this gives you:**
- Auto-bump version based on conventional commit types
- `feat` → minor bump, `fix` → patch bump, `BREAKING CHANGE` → major bump
- Auto-tag, auto-release, auto-publish

---

### 7. Documentation Generation

**Priority: LOW**
**Effort: Medium**

#### 7.1 — Python API Docs (Sphinx + autodoc)

```
docs/
├── conf.py
├── index.rst
├── api/
│   ├── neurocnl.rst
│   └── neurodreamhand.rst
└── requirements.txt
```

```python
# docs/conf.py
extensions = [
    'sphinx.ext.autodoc',
    'sphinx.ext.napoleon',  # Google-style docstrings
    'sphinx.ext.viewcode',
    'sphinx_rtd_theme',
]
html_theme = 'sphinx_rtd_theme'
```

#### 7.2 — CI Docs Build + Deploy

```yaml
# .github/workflows/docs.yml
name: Documentation
on:
  push:
    branches: [main]
    paths: ['docs/**', 'neurocnl/**/*.py', 'Neuro-Dream-Hand/**/*.py']
jobs:
  build-docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - run: pip install sphinx sphinx-rtd-theme
      - run: sphinx-build -b html docs/ docs/_build/
      - uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: docs/_build/
```

**Result:** Auto-deployed docs at `https://yoshimartodihardjo.github.io/neurocnl/`

---

### 8. Docker Build Verification

**Priority: MEDIUM**
**Effort: Small**

Add Docker build verification to CI (catches broken Dockerfiles before release):

```yaml
# Add to python_ci.yml or create .github/workflows/docker-ci.yml
  verify-docker:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build backend image
        run: docker build -t neurocnl-server:ci -f neurocnl/backend/Dockerfile neurocnl/
      - name: Build frontend image
        run: docker build -t neurocnl-studio:ci -f neurocnl/frontend/Dockerfile neurocnl/frontend/
      - name: Test docker-compose
        run: |
          cd neurocnl
          docker compose up -d
          sleep 10
          curl -f http://localhost:8000/health || exit 1
          docker compose down
```

---

### 9. Arduino / PlatformIO CI

**Priority: LOW**
**Effort: Small**

```yaml
# .github/workflows/arduino-ci.yml
name: Arduino CI
on:
  push:
    paths: ['servo_control/**']
  pull_request:
    paths: ['servo_control/**']
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: arduino/compile-sketches@v1
        with:
          fqbn: "teensy:avr:teensy40"
          sketch-paths: servo_control/
          libraries: |
            - name: Servo
```

**Alternative (PlatformIO):**
```yaml
      - uses: actions/cache@v4
        with:
          path: ~/.platformio
          key: pio-${{ hashFiles('servo_control/platformio.ini') }}
      - run: pip install platformio
      - run: pio run -d servo_control/
```

---

### 10. Branch Protection Rules

**Priority: HIGH**
**Effort: Small (GitHub Settings)**

Configure via GitHub UI or API:

```json
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "neurocnl (3.11)",
      "neuro-dream-hand (3.11)",
      "flutter",
      "security",
      "commitlint"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1
  },
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
```

**What this enforces:**
- All CI checks must pass before merging
- At least 1 review required
- No force pushes to main
- Linear history (rebase/squash only)

---

## Summary: Priority Matrix

| # | Item | Priority | Effort | Impact |
|---|------|----------|--------|--------|
| 1 | Dependabot | HIGH | Small | Keeps deps fresh, catches vulns |
| 2 | Security scanning (pip-audit + Trivy) | HIGH | Small | Detects vulnerable packages |
| 3 | Pre-commit hooks | MEDIUM | Small | Faster local feedback loop |
| 4 | Codecov integration | MEDIUM | Small | Track coverage trends, PR diffs |
| 5 | Conventional commits + changelog | MEDIUM | Small | Consistent release notes |
| 6 | Semantic versioning automation | LOW | Small | Eliminates manual version bumps |
| 7 | Sphinx documentation | LOW | Medium | Auto-generated API reference |
| 8 | Docker build verification | MEDIUM | Small | Catch broken containers in CI |
| 9 | Arduino/PlatformIO CI | LOW | Small | Verify firmware compiles |
| 10 | Branch protection | HIGH | Small | Enforce quality gates |

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `.github/dependabot.yml` | Create | Automated dependency updates |
| `.pre-commit-config.yaml` | Create | Local developer hooks |
| `.commitlintrc.yml` | Create | Commit message enforcement |
| `codecov.yml` | Create | Coverage thresholds and config |
| `cliff.toml` | Create | Changelog generation config |
| `docs/conf.py` | Create | Sphinx documentation config |
| `.github/workflows/python_ci.yml` | Modify | Add security scanning + Codecov |
| `.github/workflows/flutter_ci.yml` | Modify | Add Codecov upload |
| `.github/workflows/commitlint.yml` | Create | PR commit lint check |
| `.github/workflows/docs.yml` | Create | Auto-deploy documentation |
| `.github/workflows/docker-ci.yml` | Create | Docker build verification |
| `.github/workflows/arduino-ci.yml` | Create | Arduino compilation check |
