#!/bin/bash
# ─────────────────────────────────────────────────────────────────
#  Church Podcast Automation — Setup Script
#  Supports macOS and Linux (Ubuntu/Debian)
# ─────────────────────────────────────────────────────────────────

set -e  # Exit on any error

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

        # Add Homebrew to PATH for Apple Silicon Macs
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
            SHELL_PROFILE=""
            if [[ "$SHELL" == */zsh ]]; then
                SHELL_PROFILE="$HOME/.zprofile"
            elif [[ "$SHELL" == */bash ]]; then
                SHELL_PROFILE="$HOME/.bash_profile"
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
#  2. PYTHON
# ─────────────────────────────────────────────────────────────────
install_python() {
    header "Python 3"

    if command -v python3 &>/dev/null; then
        PY_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        PY_MAJOR=$(echo "$PY_VERSION" | cut -d. -f1)
        PY_MINOR=$(echo "$PY_VERSION" | cut -d. -f2)

        if [[ "$PY_MAJOR" -ge 3 && "$PY_MINOR" -ge 9 ]]; then
            success "Python $PY_VERSION already installed"
            PYTHON_CMD="python3"
            return
        else
            warning "Python $PY_VERSION found but 3.9+ is required. Upgrading..."
        fi
    else
        info "Python 3 not found. Installing..."
    fi

    if [[ "$OS" == "macos" ]]; then
        brew install python@3.12
        brew link --overwrite python@3.12 2>/dev/null || true
    elif [[ "$OS" == "debian" ]]; then
        sudo apt-get update -q
        sudo apt-get install -y python3 python3-pip python3-venv
    elif [[ "$OS" == "redhat" ]]; then
        sudo dnf install -y python3 python3-pip
    fi

    PYTHON_CMD="python3"
    success "Python $(python3 --version) installed"
}

# ─────────────────────────────────────────────────────────────────
#  3. PIP
# ─────────────────────────────────────────────────────────────────
ensure_pip() {
    header "pip"
    if ! $PYTHON_CMD -m pip --version &>/dev/null; then
        info "pip not found. Installing..."
        if [[ "$OS" == "macos" ]]; then
            brew install python@3.12
        else
            sudo apt-get install -y python3-pip
        fi
    fi
    $PYTHON_CMD -m pip install --upgrade pip --quiet
    success "pip $($PYTHON_CMD -m pip --version | awk '{print $2}') ready"
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
            sudo apt-get update -q
            sudo apt-get install -y ffmpeg
        elif [[ "$OS" == "redhat" ]]; then
            sudo dnf install -y https://download1.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm 2>/dev/null || true
            sudo dnf install -y ffmpeg
        fi
        success "ffmpeg installed"
    fi
}

# ─────────────────────────────────────────────────────────────────
#  5. PYTHON DEPENDENCIES
# ─────────────────────────────────────────────────────────────────
install_python_deps() {
    header "Python packages"

    REQUIREMENTS_FILE="$(dirname "$0")/requirements.txt"

    if [[ -f "$REQUIREMENTS_FILE" ]]; then
        info "Installing from requirements.txt..."
        $PYTHON_CMD -m pip install -r "$REQUIREMENTS_FILE" --quiet
    else
        info "requirements.txt not found. Installing packages directly..."
        $PYTHON_CMD -m pip install \
            yt-dlp \
            google-auth \
            google-auth-oauthlib \
            google-api-python-client \
            requests \
            tqdm \
            --quiet
    fi

    success "All Python packages installed"
}

# ─────────────────────────────────────────────────────────────────
#  6. VERIFY EVERYTHING
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

    check "Python 3"         "command -v python3"
    check "pip"              "$PYTHON_CMD -m pip --version"
    check "ffmpeg"           "command -v ffmpeg"
    check "yt-dlp"           "$PYTHON_CMD -m yt_dlp --version"
    check "google-auth"      "$PYTHON_CMD -c 'import google.auth'"
    check "googleapiclient"  "$PYTHON_CMD -c 'import googleapiclient'"

    if $ALL_OK; then
        echo ""
        echo -e "${GREEN}${BOLD}🎉 Setup complete! Everything is installed and ready.${RESET}"
    else
        echo ""
        warning "Some items may not have installed correctly. Review the output above."
    fi
}

# ─────────────────────────────────────────────────────────────────
#  NEXT STEPS REMINDER
# ─────────────────────────────────────────────────────────────────
print_next_steps() {
    echo ""
    echo -e "${BOLD}Next steps:${RESET}"
    echo "  1. Get your YouTube OAuth credentials:"
    echo "     https://console.cloud.google.com → APIs & Services → Credentials"
    echo "     Download as 'client_secrets.json' and place it in this folder."
    echo ""
    echo "  2. Edit the CONFIG block in church_podcast_automation.py:"
    echo "     - Set your YouTube channel ID"
    echo "     - Set your preferred episode title prefix and description"
    echo ""
    echo "  3. Run the script every Monday:"
    echo "     python3 church_podcast_automation.py"
    echo ""
    echo "  See README.md for the full setup guide."
    echo ""
}

# ─────────────────────────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Church Podcast Automation — Setup${RESET}"
echo "────────────────────────────────────"

detect_os

if [[ "$OS" == "macos" ]]; then
    install_homebrew
fi

install_python
ensure_pip
install_ffmpeg
install_python_deps
verify_installation
print_next_steps
