#!/usr/bin/env bash
# setup.sh — One-command NeuroCNL setup
# Usage: curl -fsSL https://raw.githubusercontent.com/yoshimartodihardjo/Neuro-space/main/scripts/setup.sh | bash
#    or: ./setup.sh [version]
set -euo pipefail

VERSION="${1:-latest}"
ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

# Map architecture
case "$ARCH" in
  x86_64|amd64) ARCH="x86_64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Map OS name for backend artifact
case "$OS" in
  linux) PLATFORM="linux" ;;
  darwin) PLATFORM="macos" ;;
  *) echo "❌ Unsupported OS: $OS (use setup.ps1 for Windows)"; exit 1 ;;
esac

BASE_URL="https://github.com/yoshimartodihardjo/Neuro-space/releases"
if [ "$VERSION" = "latest" ]; then
  BASE_URL="${BASE_URL}/latest/download"
else
  BASE_URL="${BASE_URL}/download/${VERSION}"
fi

INSTALL_DIR="${HOME}/.neurocnl"
mkdir -p "$INSTALL_DIR"

echo "🧠 NeuroCNL Setup"
echo "   Version: ${VERSION}"
echo "   Platform: ${PLATFORM}-${ARCH}"
echo "   Install dir: ${INSTALL_DIR}"
echo ""

# Download backend
echo "⬇️  Downloading NeuroCNL Server (${PLATFORM}-${ARCH})..."
BACKEND_FILE="neurocnl-server-${PLATFORM}-${ARCH}.tar.gz"
curl -fSL "${BASE_URL}/${BACKEND_FILE}" -o "${INSTALL_DIR}/${BACKEND_FILE}" || {
  echo "⚠️  Backend download failed. Check release exists at:"
  echo "   ${BASE_URL}/${BACKEND_FILE}"
  echo ""
  echo "Alternatives:"
  echo "  pip install neurocnl[server]"
  echo "  docker run -p 8000:8000 ghcr.io/yoshimartodihardjo/neurocnl-server:latest"
}

# Download frontend
echo "⬇️  Downloading NeuroCNL Studio (${PLATFORM})..."
FRONTEND_FILE="neurocnl-studio-${PLATFORM}.tar.gz"
curl -fSL "${BASE_URL}/${FRONTEND_FILE}" -o "${INSTALL_DIR}/${FRONTEND_FILE}" || {
  echo "⚠️  Frontend download failed."
}

# Extract
echo "📦 Extracting..."
cd "$INSTALL_DIR"
[ -f "$BACKEND_FILE" ] && tar xzf "$BACKEND_FILE" && rm "$BACKEND_FILE"
[ -f "$FRONTEND_FILE" ] && tar xzf "$FRONTEND_FILE" && rm "$FRONTEND_FILE"

echo ""
echo "✅ Installation complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  To start the backend server:"
echo "    ${INSTALL_DIR}/neurocnl-server --port 8000"
echo ""
echo "  To launch the studio:"
echo "    ${INSTALL_DIR}/neurocnl-studio"
echo ""
echo "  Or use Docker:"
echo "    docker run -p 8000:8000 ghcr.io/yoshimartodihardjo/neurocnl-server:latest"
echo ""
echo "  Or install via pip:"
echo "    pip install neurocnl[server]"
echo "    neurocnl-server --port 8000"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
