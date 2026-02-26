#!/bin/bash
# ─────────────────────────────────────────────────────────────────
#  Church Podcast Automation — Setup Script
#  Supports macOS and Linux (Ubuntu/Debian)
# ─────────────────────────────────────────────────────────────────

set -e  # Exit on any error

VENV_DIR="$(dirname "$0")/.venv"

# ── Colors ────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────
info()    { echo -e "${BLUE}ℹ ${RESET}$1"; }
success() { echo -e "${GREEN}✓ ${RESET}$1"; }
warning() { echo -e "${YELLOW}⚠ ${RESET}$1"; }
error()   { echo -e "${RED}✗ ${RESET}$1"; exit 1; }
header()  { echo -e "\n${BOLD}${BLUE}── $1 ${RESET}"; }

# ── Detect OS ─────────────────────────────────────────────────────
detect_os() {
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
}

# ─────────────────────────────────────────────────────────────────
#  1. HOMEBREW (macOS only)
# ─────────────────────────────────────────────────────────────────
install_homebrew() {
    header "Homebrew"
    if command -v brew &>/dev/null; then
        success "Homebrew already installed ($(brew --version | head -1))"
    else
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
            SHELL_PROFILE=""
            if [[ "$SHELL" == */zsh ]]; then SHELL_PROFILE="$HOME/.zprofile"
            elif [[ "$SHELL" == */bash ]]; then SHELL_PROFILE="$HOME/.bash_profile"
            fi
            if [[ -n "$SHELL_PROFILE" ]]; then
                echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$SHELL_PROFILE"
                info "Added Homebrew to $SHELL_PROFILE"
            fi
        fi
        success "Homebrew installed"
    fi
}

# ─────────────────────────────────────────────────────────────────
#  2. PYTHON 3.12
# ─────────────────────────────────────────────────────────────────
install_python() {
    header "Python 3.12"

    if [[ "$OS" == "macos" ]]; then
        brew install python@3.12

        # Resolve the exact binary path from Homebrew — works on both
        # Apple Silicon (/opt/homebrew) and Intel (/usr/local)
        BREW_PREFIX=$(brew --prefix)
        PYTHON_CMD="$BREW_PREFIX/opt/python@3.12/bin/python3.12"

        if [[ ! -f "$PYTHON_CMD" ]]; then
            error "python3.12 not found at $PYTHON_CMD. Try: brew reinstall python@3.12"
        fi

    elif [[ "$OS" == "debian" ]]; then
        sudo apt-get update -q
        sudo apt-get install -y python3.12 python3.12-venv python3-pip
        PYTHON_CMD="python3.12"

    elif [[ "$OS" == "redhat" ]]; then
        sudo dnf install -y python3.12 python3-pip
        PYTHON_CMD="python3.12"
    fi

    success "Using $($PYTHON_CMD --version)"
}

# ─────────────────────────────────────────────────────────────────
#  3. VIRTUAL ENVIRONMENT
#  All packages are installed into .venv so we never touch the
#  system or Homebrew Python — avoids the "externally managed
#  environment" error introduced in Python 3.12 / PEP 668.
# ─────────────────────────────────────────────────────────────────
setup_venv() {
    header "Virtual environment (.venv)"

    if [[ -d "$VENV_DIR" ]]; then
        info ".venv already exists, updating packages..."
    else
        info "Creating .venv with $($PYTHON_CMD --version)..."
        $PYTHON_CMD -m venv "$VENV_DIR"
        success ".venv created at $VENV_DIR"
    fi

    # Always use the venv's Python from here on
    PYTHON_CMD="$VENV_DIR/bin/python"
    PIP_CMD="$VENV_DIR/bin/pip"

    $PIP_CMD install --upgrade pip --quiet
    success "Virtual environment ready"
}

# ─────────────────────────────────────────────────────────────────
#  4. FFMPEG
# ─────────────────────────────────────────────────────────────────
install_ffmpeg() {
    header "ffmpeg"
    if command -v ffmpeg &>/dev/null; then
        success "ffmpeg already installed ($(ffmpeg -version 2>&1 | head -1 | awk '{print $3}'))"
    else
        info "Installing ffmpeg..."
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
}

# ─────────────────────────────────────────────────────────────────
#  5. PYTHON DEPENDENCIES (into .venv)
# ─────────────────────────────────────────────────────────────────
install_python_deps() {
    header "Python packages"

    REQUIREMENTS_FILE="$(dirname "$0")/requirements.txt"

    if [[ -f "$REQUIREMENTS_FILE" ]]; then
        info "Installing from requirements.txt into .venv..."
        $PIP_CMD install -r "$REQUIREMENTS_FILE" --quiet
    else
        info "requirements.txt not found. Installing packages directly..."
        $PIP_CMD install \
            yt-dlp \
            google-auth \
            google-auth-oauthlib \
            google-api-python-client \
            requests \
            tqdm \
            --quiet
    fi

    success "All Python packages installed into .venv"
}

# ─────────────────────────────────────────────────────────────────
#  6. WRITE run.sh HELPER
#  So the user never has to remember to activate the venv manually.
# ─────────────────────────────────────────────────────────────────
write_run_script() {
    header "Creating run.sh"

    RUN_SCRIPT="$(dirname "$0")/run.sh"
    cat > "$RUN_SCRIPT" << EOF
#!/bin/bash
# Runs church_podcast_automation.py inside the .venv automatically.
SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
"\$SCRIPT_DIR/.venv/bin/python" "\$SCRIPT_DIR/church_podcast_automation.py" "\$@"
EOF
    chmod +x "$RUN_SCRIPT"
    success "run.sh created — use this every Monday instead of calling python3 directly"
}

# ─────────────────────────────────────────────────────────────────
#  7. VERIFY
# ─────────────────────────────────────────────────────────────────
verify_installation() {
    header "Verifying installation"
    ALL_OK=true

    check() {
        local label=$1
        local cmd=$2
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
    check "google-auth"              "$PYTHON_CMD -c 'import google.auth'"
    check "googleapiclient"          "$PYTHON_CMD -c 'import googleapiclient'"
    check "OpenSSL (not LibreSSL)"   "$PYTHON_CMD -c \"import ssl; assert 'LibreSSL' not in ssl.OPENSSL_VERSION\""

    if $ALL_OK; then
        echo ""
        echo -e "${GREEN}${BOLD}🎉 Setup complete!${RESET}"
    else
        echo ""
        warning "Some items may not have installed correctly. Review the output above."
    fi
}

# ─────────────────────────────────────────────────────────────────
#  NEXT STEPS
# ─────────────────────────────────────────────────────────────────
print_next_steps() {
    echo ""
    echo -e "${BOLD}Every Monday, just run:${RESET}"
    echo "  ./run.sh"
    echo ""
    echo -e "${BOLD}First-time setup:${RESET}"
    echo "  1. Download OAuth credentials from https://console.cloud.google.com"
    echo "     Save as 'client_secrets.json' in this folder."
    echo "  2. Edit the CONFIG block in church_podcast_automation.py"
    echo "     with your YouTube channel ID and episode defaults."
    echo ""
    echo "  See README.md for the full guide."
    echo ""
}

# ─────────────────────────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Church Podcast Automation — Setup${RESET}"
echo "────────────────────────────────────"

detect_os
[[ "$OS" == "macos" ]] && install_homebrew
install_python
setup_venv
install_ffmpeg
install_python_deps
write_run_script
verify_installation
print_next_steps
