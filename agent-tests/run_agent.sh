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
