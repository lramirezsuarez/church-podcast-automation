#!/bin/bash
# ─────────────────────────────────────────────────────────────────
#  Church Podcast — Setup Script
#  Run once from the project root before using the CLI or the app.
#
#  What it does:
#    1. Detects macOS / Linux
#    2. Installs Homebrew (macOS only, if missing)
#    3. Installs Python 3.12 via Homebrew / apt
#    4. Creates .venv at <project-root>/.venv
#    5. Installs all Python deps (CLI + Flask server) into .venv
#    6. Checks for ffmpeg (required at runtime)
#    7. Writes run.sh — a one-command CLI launcher
#    8. Verifies everything and prints a summary
# ─────────────────────────────────────────────────────────────────

set -e

# Project root = the folder containing this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"
REQUIREMENTS="$SCRIPT_DIR/python-server/requirements.txt"

# ── Colours ───────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${BLUE}ℹ ${RESET}$1"; }
success() { echo -e "${GREEN}✓ ${RESET}$1"; }
warning() { echo -e "${YELLOW}⚠ ${RESET}$1"; }
error()   { echo -e "${RED}✗ ${RESET}$1"; exit 1; }
header()  { echo -e "\n${BOLD}${BLUE}── $1 ${RESET}"; }

echo ""
echo -e "${BOLD}Church Podcast — Setup${RESET}"
echo "──────────────────────────────────────"

# ─────────────────────────────────────────────────────────────────
#  DETECT OS
# ─────────────────────────────────────────────────────────────────
header "Detecting OS"
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ -f /etc/debian_version ]]; then
    OS="debian"
elif [[ -f /etc/redhat-release ]]; then
    OS="redhat"
else
    error "Unsupported OS. This script supports macOS and Debian/Ubuntu Linux."
fi
info "Detected OS: $OS"

# ─────────────────────────────────────────────────────────────────
#  HOMEBREW (macOS only)
# ─────────────────────────────────────────────────────────────────
if [[ "$OS" == "macos" ]]; then
    header "Homebrew"
    if command -v brew &>/dev/null; then
        success "Homebrew already installed ($(brew --version | head -1))"
    else
        info "Installing Homebrew…"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        # Add Homebrew to PATH for the rest of this script
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
            for profile in "$HOME/.zprofile" "$HOME/.bash_profile"; do
                if [[ -f "$profile" ]]; then
                    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$profile"
                    info "Added Homebrew to $profile"
                    break
                fi
            done
        fi
        success "Homebrew installed"
    fi
fi

# ─────────────────────────────────────────────────────────────────
#  PYTHON 3.12
# ─────────────────────────────────────────────────────────────────
header "Python 3.12"
PYTHON_CMD=""

if [[ "$OS" == "macos" ]]; then
    brew install python@3.12
    BREW_PREFIX=$(brew --prefix)
    PYTHON_CMD="$BREW_PREFIX/opt/python@3.12/bin/python3.12"
    [[ -f "$PYTHON_CMD" ]] || error "python3.12 not found at $PYTHON_CMD — try: brew reinstall python@3.12"

elif [[ "$OS" == "debian" ]]; then
    sudo apt-get update -q
    sudo apt-get install -y python3.12 python3.12-venv python3-pip
    PYTHON_CMD="python3.12"

elif [[ "$OS" == "redhat" ]]; then
    sudo dnf install -y python3.12 python3-pip
    PYTHON_CMD="python3.12"
fi

success "Using $($PYTHON_CMD --version)"

# ─────────────────────────────────────────────────────────────────
#  VIRTUAL ENVIRONMENT  (.venv at project root)
# ─────────────────────────────────────────────────────────────────
header "Virtual environment (.venv)"

if [[ -d "$VENV_DIR" ]]; then
    info ".venv already exists — updating packages…"
else
    info "Creating .venv at $VENV_DIR …"
    "$PYTHON_CMD" -m venv "$VENV_DIR"
    success ".venv created"
fi

# Switch to the venv's own python from here on — all installs go here
PYTHON_CMD="$VENV_DIR/bin/python"
PIP_CMD="$VENV_DIR/bin/pip"

"$PIP_CMD" install --upgrade pip --quiet
success "Virtual environment ready"

# ─────────────────────────────────────────────────────────────────
#  FFMPEG  (checked here; installed if missing)
# ─────────────────────────────────────────────────────────────────
header "ffmpeg"
if command -v ffmpeg &>/dev/null; then
    success "ffmpeg already installed ($(ffmpeg -version 2>&1 | head -1 | awk '{print $3}'))"
else
    info "Installing ffmpeg…"
    if [[ "$OS" == "macos" ]]; then
        brew install ffmpeg
    elif [[ "$OS" == "debian" ]]; then
        sudo apt-get update -q && sudo apt-get install -y ffmpeg
    elif [[ "$OS" == "redhat" ]]; then
        sudo dnf install -y https://download1.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm 2>/dev/null || true
        sudo dnf install -y ffmpeg
    fi
    success "ffmpeg installed"
fi

# ─────────────────────────────────────────────────────────────────
#  PYTHON PACKAGES  (CLI deps + Flask server deps)
# ─────────────────────────────────────────────────────────────────
header "Python packages"
if [[ -f "$REQUIREMENTS" ]]; then
    info "Installing from python-server/requirements.txt into .venv…"
    "$PIP_CMD" install -r "$REQUIREMENTS" --quiet
    success "All packages installed into .venv"
else
    error "requirements.txt not found at $REQUIREMENTS"
fi

# ─────────────────────────────────────────────────────────────────
#  run.sh — CLI launcher (uses .venv/bin/python automatically)
# ─────────────────────────────────────────────────────────────────
header "Creating run.sh"
cat > "$SCRIPT_DIR/run.sh" << 'RUNSCRIPT'
#!/bin/bash
# Runs the Church Podcast CLI using the .venv Python automatically.
# Usage:  ./run.sh  [flags]
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/.venv/bin/python" "$SCRIPT_DIR/python-server/church_podcast_automation.py" "$@"
RUNSCRIPT
chmod +x "$SCRIPT_DIR/run.sh"
success "run.sh created"

# ─────────────────────────────────────────────────────────────────
#  VERIFY
# ─────────────────────────────────────────────────────────────────
header "Verifying installation"
ALL_OK=true

check() {
    local label=$1; local cmd=$2
    if eval "$cmd" &>/dev/null; then
        success "$label"
    else
        warning "$label — NOT FOUND (something may have gone wrong)"
        ALL_OK=false
    fi
}

check "Python 3.10+ in .venv"   "$PYTHON_CMD -c 'import sys; exit(0 if sys.version_info >= (3,10) else 1)'"
check "ffmpeg"                   "command -v ffmpeg"
check "yt-dlp"                   "$PYTHON_CMD -m yt_dlp --version"
check "flask"                    "$PYTHON_CMD -c 'import flask'"
check "google-auth"              "$PYTHON_CMD -c 'import google.auth'"
check "googleapiclient"          "$PYTHON_CMD -c 'import googleapiclient'"
check "OpenSSL (not LibreSSL)"   "$PYTHON_CMD -c \"import ssl; assert 'LibreSSL' not in ssl.OPENSSL_VERSION\""

# ─────────────────────────────────────────────────────────────────
#  NEXT STEPS
# ─────────────────────────────────────────────────────────────────
echo ""
if $ALL_OK; then
    echo -e "${GREEN}${BOLD}🎉 Setup complete!${RESET}"
else
    warning "Some items may not have installed correctly. Review the output above."
fi

echo ""
echo -e "${BOLD}CLI — every Monday, just run:${RESET}"
echo "  ./run.sh"
echo ""
echo -e "${BOLD}Mac App — open in Xcode and press ⌘R:${RESET}"
echo "  open ChurchPodcast.xcodeproj"
echo ""
echo -e "${BOLD}First-time setup required:${RESET}"
echo "  1. Copy your client_secrets.json to this folder (see README)"
echo "  2. Edit CONFIG in python-server/church_podcast_automation.py"
echo "     to set your YouTube channel ID and episode defaults"
echo ""
echo "  See README.md for the full guide."
echo ""
