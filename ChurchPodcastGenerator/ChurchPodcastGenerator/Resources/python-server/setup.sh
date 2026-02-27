#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  Church Podcast App — Backend Setup
#  Run this once from the repo root before opening Xcode.
# ─────────────────────────────────────────────────────────────

set -e
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
VENV="$REPO_ROOT/.venv"
PYTHON=""

echo ""
echo "═══════════════════════════════════════════"
echo "  Church Podcast — Backend Setup"
echo "═══════════════════════════════════════════"
echo ""

# ── 1. Find Python 3.10+ ────────────────────────────────────
find_python() {
    for candidate in \
        "/opt/homebrew/opt/python@3.12/bin/python3.12" \
        "/usr/local/opt/python@3.12/bin/python3.12" \
        "/opt/homebrew/opt/python@3.11/bin/python3.11" \
        "python3.12" "python3.11" "python3.10" "python3"
    do
        if command -v "$candidate" &>/dev/null; then
            version=$("$candidate" -c "import sys; print(sys.version_info[:2])")
            if [[ "$version" > "(3, 9)" ]]; then
                echo "$candidate"
                return
            fi
        fi
    done
}

PYTHON=$(find_python)
if [[ -z "$PYTHON" ]]; then
    echo "✗  Python 3.10+ not found."
    echo "   Install it with: brew install python@3.12"
    exit 1
fi
echo "✓  Using Python: $PYTHON ($($PYTHON --version))"

# ── 2. Create virtual environment ───────────────────────────
if [[ ! -d "$VENV" ]]; then
    echo "▶  Creating virtual environment at .venv ..."
    "$PYTHON" -m venv "$VENV"
fi
echo "✓  Virtual environment: $VENV"

# ── 3. Install dependencies ──────────────────────────────────
echo "▶  Installing Python dependencies..."
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet -r "$REPO_ROOT/python-server/requirements.txt"
echo "✓  Dependencies installed"

# ── 4. Check ffmpeg ──────────────────────────────────────────
if command -v ffmpeg &>/dev/null; then
    echo "✓  ffmpeg found: $(ffmpeg -version 2>&1 | head -1)"
else
    echo "⚠  ffmpeg not found — install with: brew install ffmpeg"
fi

# ── 5. Verify server starts ──────────────────────────────────
echo ""
echo "▶  Verifying server starts..."
"$VENV/bin/python" "$REPO_ROOT/python-server/server.py" &
SERVER_PID=$!
sleep 2

if curl -sf http://localhost:5001/status > /dev/null 2>&1; then
    echo "✓  Server responds on http://localhost:5001"
else
    echo "⚠  Server did not respond — check python-server/server.py manually"
fi
kill $SERVER_PID 2>/dev/null || true

# ── 6. Summary ───────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "  ✅  Setup complete!"
echo "═══════════════════════════════════════════"
echo ""
echo "  Next steps:"
echo "  1. Copy client_secrets.json to the repo root (see README)"
echo "  2. Open SwiftUI/ChurchPodcast/ChurchPodcast.xcodeproj in Xcode"
echo "  3. Press ⌘R to run"
echo ""
echo "  The app will start the Python server automatically."
echo "  You can also run the server manually:"
echo "  .venv/bin/python python-server/server.py"
echo ""
