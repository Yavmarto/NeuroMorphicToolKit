# T4-4: Create one-command development setup script

- **Problem:** Setting up the full dev environment requires manual steps across 7+ directories.
- **Fix:** Create `scripts/dev-setup.sh` that:
  1. Inits and updates all git submodules
  2. Creates a shared Python venv or per-module venvs
  3. Installs all Python backends in editable mode
  4. Runs `flutter pub get` in all frontend directories
  5. Verifies all health endpoints
- **Effort:** 1 day
