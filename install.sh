#!/bin/sh
# ==============================================================================
# oogrep Universal Installer
# "Capability-bounded recursive regex search with a first-class MCP surface."
#
# Usage:
#   curl -fsSL https://openooda-tools.github.io/oogrep/install.sh | bash
#
# Options:
#   --prefix <dir>   Installation directory (default: /usr/local/bin or ~/.local/bin)
#   --apt, --deb     Install Debian package (.deb) via apt/dpkg
#   --dnf, --rpm     Install RPM package (.rpm) via dnf
#   --pkgbuild, --arch Install Arch Linux package via PKGBUILD / makepkg
#   --dry-run        Simulate installation without touching the filesystem
#   --verify         Perform strict cryptographic SHA-256 integrity verification
#   --uninstall      Remove oogrep binary or package from standard system paths
#   -h, --help       Show this help message
# ==============================================================================

set -eu

REPO="openOODA-tools/oogrep"
GITHUB_URL="https://github.com/${REPO}"
CANONICAL_URL="https://openooda-tools.github.io/oogrep"
VERSION_PIN="v0.3.1"
RAW_VERSION="0.3.1"

# --- Styling & Human Interface Standard ---------------------------------------
if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    AMBER="\033[38;5;214m"
    CYAN="\033[38;5;51m"
    GREEN="\033[38;5;82m"
    YELLOW="\033[38;5;220m"
    MAGENTA="\033[38;5;213m"
    DIM="\033[38;5;242m"
    BOLD="\033[1m"
    RESET="\033[0m"
    IS_TTY=1
else
    AMBER="" CYAN="" GREEN="" YELLOW="" MAGENTA="" DIM="" BOLD="" RESET=""
    IS_TTY=0
fi

say()  { printf '%b\n' "$*"; }
dim()  { say "  ${DIM}$*${RESET}"; }
ok()   { say "  ${GREEN}✔${RESET} $*"; }
warn() { say "  ${YELLOW}!${RESET} $*"; }
err()  { say "  ${YELLOW}ERROR:${RESET} $*" >&2; }
step() { say ""; say " ${CYAN}${BOLD}$*${RESET}"; }

pause() {
    _s="${1:-0.25}"
    if [ "$IS_TTY" -eq 1 ]; then
        sleep "$_s" 2>/dev/null || true
    fi
}

story_line() {
    say "  ${MAGENTA}›${RESET} ${DIM}$*${RESET}"
    pause 0.2
}

spin_while() {
    _pid="$1"
    _label="$2"
    _i=0
    if [ "$IS_TTY" -eq 0 ]; then
        wait "$_pid"
        return $?
    fi
    while kill -0 "$_pid" 2>/dev/null; do
        case $((_i % 4)) in
            0) _ch='⠋' ;;
            1) _ch='⠙' ;;
            2) _ch='⠹' ;;
            3) _ch='⠸' ;;
        esac
        printf "\r  ${CYAN}%s${RESET} %s…  " "$_ch" "$_label"
        _i=$((_i + 1))
        sleep 0.08 2>/dev/null || true
    done
    wait "$_pid"
    _rc=$?
    printf '\r\033[K'
    return $_rc
}

countdown() {
    _n="${1:-3}"
    _msg="${2:-Launching}"
    if [ "$IS_TTY" -eq 0 ]; then
        return 0
    fi
    while [ "$_n" -gt 0 ]; do
        printf "\r  ${AMBER}${BOLD}%s${RESET} in ${BOLD}%s${RESET}…   " "$_msg" "$_n"
        sleep 0.8
        _n=$((_n - 1))
    done
    printf '\r\033[K'
}

clear_soft() {
    if [ "$IS_TTY" -eq 1 ] && command -v clear >/dev/null 2>&1; then
        clear 2>/dev/null || true
    fi
}

banner() {
    clear_soft
    say ""
    say "${AMBER}${BOLD}"
    cat <<'BANNER'
        ╔══════════════════════════════════════════════════════════╗
        ║                                                          ║
        ║   ██████╗  ██████╗  ██████╗ ██████╗ ███████╗██████╗      ║
        ║  ██╔═══██╗██╔═══██╗██╔════╝ ██╔══██╗██╔════╝██╔══██╗     ║
        ║  ██║   ██║██║   ██║██║  ███╗██████╔╝█████╗  ██████╔╝     ║
        ║  ██║   ██║██║   ██║██║   ██║██╔══██╗██╔══╝  ██╔═══╝      ║
        ║  ╚██████╔╝╚██████╔╝╚██████╔╝██║  ██║███████╗██║          ║
        ║   ╚═════╝  ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝          ║
        ║                                                          ║
        ║                openOODA Recursive Search                 ║
        ║         Fast / Capability-Bounded / Agent-Ready          ║
        ║                                                          ║
        ╚══════════════════════════════════════════════════════════╝
BANNER
    say "${RESET}"
    say "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    say ""
}

victory_banner() {
    say ""
    say "${GREEN}${BOLD}"
    cat <<'VICTORY'
        ╔══════════════════════════════════════════════════════════╗
        ║                                                          ║
        ║               ⚡ SOVEREIGNTY AWAKENED ⚡                  ║
        ║                                                          ║
        ╚══════════════════════════════════════════════════════════╝
VICTORY
    say "${RESET}"
    say "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    say ""
}

# --- Argument Parsing ---------------------------------------------------------
DRY_RUN=0
DO_UNINSTALL=0
DO_VERIFY=0
INSTALL_APT=0
INSTALL_DNF=0
INSTALL_ARCH=0
ASSUME_YES=0
CUSTOM_PREFIX=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --uninstall) DO_UNINSTALL=1; shift ;;
        -y|--yes) ASSUME_YES=1; shift ;;
        --verify) DO_VERIFY=1; shift ;;
        --apt|--deb) INSTALL_APT=1; shift ;;
        --dnf|--rpm) INSTALL_DNF=1; shift ;;
        --pkgbuild|--arch) INSTALL_ARCH=1; shift ;;
        --prefix) CUSTOM_PREFIX="$2"; shift 2 ;;
        -h|--help)
            banner
            say "  ${BOLD}Usage:${RESET} curl -fsSL .../install.sh | bash [options]"
            say ""
            say "  ${BOLD}Options:${RESET}"
            say "    ${CYAN}--prefix <dir>${RESET}   Target binary directory (default: /usr/local/bin or ~/.local/bin)"
            say "    ${CYAN}--apt, --deb${RESET}     Install Debian package (.deb) via apt/dpkg"
            say "    ${CYAN}--dnf, --rpm${RESET}     Install RPM package (.rpm) via dnf"
            say "    ${CYAN}--pkgbuild, --arch${RESET} Install Arch Linux package via PKGBUILD / makepkg"
            say "    ${CYAN}--dry-run${RESET}        Simulate deployment or removal without modifying host"
            say "    ${CYAN}-y, --yes${RESET}        Non-interactive mode (auto-confirm removal)"
            say "    ${CYAN}--verify${RESET}         Verify cryptographic SHA-256 seal and exit"
            say "    ${CYAN}--uninstall${RESET}      Cleanly remove oogrep binary or package from system"
            say "    ${CYAN}-h, --help${RESET}       Display this manual"
            say ""
            exit 0
            ;;
        *) err "Unknown flag: $1"; exit 1 ;;
    esac
done

banner
story_line "Attuning your environment to openOODA recursive search…"
pause 0.3

# --- Uninstall Path -----------------------------------------------------------
if [ "$DO_UNINSTALL" -eq 1 ]; then
    step "Relinquishing oogrep from host"

    if [ "$ASSUME_YES" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
        CONFIRMED=0
        if [ -t 0 ]; then
            printf "  Are you sure you want to remove oogrep from this system? [y/N] "
            read -r ANSWER
            case "$ANSWER" in
                [yY]|[yY][eE][sS]) CONFIRMED=1 ;;
            esac
        elif [ -e /dev/tty ]; then
            printf "  Are you sure you want to remove oogrep from this system? [y/N] " </dev/tty
            read -r ANSWER </dev/tty
            case "$ANSWER" in
                [yY]|[yY][eE][sS]) CONFIRMED=1 ;;
            esac
        else
            CONFIRMED=1
        fi
        if [ "$CONFIRMED" -eq 0 ]; then
            say ""
            warn "Uninstallation cancelled by user."
            say ""
            exit 0
        fi
    fi

    FOUND=0

    # 1. Package Manager Uninstallation
    if command -v dpkg >/dev/null 2>&1 && dpkg -s oogrep >/dev/null 2>&1; then
        if [ "$DRY_RUN" -eq 1 ]; then
            dim "Would remove Debian package via apt/dpkg"
            FOUND=1
        else
            if sudo apt-get remove -y oogrep 2>/dev/null || sudo dpkg -r oogrep 2>/dev/null; then
                ok "Banished Debian package (${BOLD}oogrep${RESET})"
                FOUND=1
            fi
        fi
    elif command -v rpm >/dev/null 2>&1 && rpm -q oogrep >/dev/null 2>&1; then
        if [ "$DRY_RUN" -eq 1 ]; then
            dim "Would remove RPM package via dnf/rpm"
            FOUND=1
        else
            if sudo dnf remove -y oogrep 2>/dev/null || sudo rpm -e oogrep 2>/dev/null; then
                ok "Banished RPM package (${BOLD}oogrep${RESET})"
                FOUND=1
            fi
        fi
    elif command -v pacman >/dev/null 2>&1; then
        if pacman -Qi oogrep >/dev/null 2>&1; then
            if [ "$DRY_RUN" -eq 1 ]; then
                dim "Would remove Arch package (oogrep) via pacman"
                FOUND=1
            else
                if sudo pacman -R --noconfirm oogrep 2>/dev/null; then
                    ok "Banished Arch package (${BOLD}oogrep${RESET})"
                    FOUND=1
                fi
            fi
        fi
        if pacman -Qi oogrep-bin >/dev/null 2>&1; then
            if [ "$DRY_RUN" -eq 1 ]; then
                dim "Would remove Arch package (oogrep-bin) via pacman"
                FOUND=1
            else
                if sudo pacman -R --noconfirm oogrep-bin 2>/dev/null; then
                    ok "Banished Arch package (${BOLD}oogrep-bin${RESET})"
                    FOUND=1
                fi
            fi
        fi
    fi

    # 2. Standalone Binary Artifacts
    SEARCH_DIRS="/usr/local/bin ${HOME}/.local/bin ${HOME}/.openooda/bin /usr/bin /bin"
    if [ -n "$CUSTOM_PREFIX" ]; then
        SEARCH_DIRS="${CUSTOM_PREFIX} ${SEARCH_DIRS}"
    fi

    for d in $SEARCH_DIRS; do
        for file in "${d}/oogrep" "${d}/oogrep-uninstall"; do
            if [ -f "$file" ] || [ -L "$file" ]; then
                if [ "$DRY_RUN" -eq 1 ]; then
                    dim "Would remove $file"
                    FOUND=1
                else
                    if rm -f "$file" 2>/dev/null || sudo rm -f "$file" 2>/dev/null; then
                        ok "Banished ${BOLD}$file${RESET}"
                        FOUND=1
                    fi
                fi
            fi
        done
    done

    # 3. Completions, Man Pages, and Caches
    for f in "/etc/bash_completion.d/oogrep" "/usr/local/share/zsh/site-functions/_oogrep" "${HOME}/.local/share/zsh/site-functions/_oogrep" "${HOME}/.config/fish/completions/oogrep.fish" "/usr/local/share/man/man1/oogrep.1" "/usr/local/share/man/man1/oogrep.1.gz" "${HOME}/.local/share/man/man1/oogrep.1" "${HOME}/.local/share/man/man1/oogrep.1.gz"; do
        if [ -f "$f" ] || [ -L "$f" ]; then
            if [ "$DRY_RUN" -eq 1 ]; then
                dim "Would remove $f"
                FOUND=1
            else
                rm -f "$f" 2>/dev/null || sudo rm -f "$f" 2>/dev/null || true
                ok "Removed $f"
                FOUND=1
            fi
        fi
    done

    for c in "${HOME}/.cache/oogrep" "${HOME}/.config/oogrep"; do
        if [ -d "$c" ]; then
            if [ "$DRY_RUN" -eq 1 ]; then
                dim "Would remove directory $c"
                FOUND=1
            else
                rm -rf "$c" 2>/dev/null || true
                ok "Removed directory $c"
                FOUND=1
            fi
        fi
    done

    say ""
    if [ "$FOUND" -eq 0 ]; then
        warn "No existing oogrep binary, uninstaller, package, or cache detected on this host."
    else
        if [ "$DRY_RUN" -eq 1 ]; then
            ok "Dry run complete. No host modifications made."
        else
            ok "${BOLD}oogrep has been cleanly relinquished from this host.${RESET}"
        fi
    fi
    say ""
    exit 0
fi

# --- APT / DEB Installation ---
if [ "$INSTALL_APT" -eq 1 ]; then
    step "Installing oogrep via APT/dpkg (${VERSION_PIN})"
    DEB_NAME="oogrep_${RAW_VERSION}-1_amd64.deb"
    DEB_URL="${GITHUB_URL}/releases/download/${VERSION_PIN}/${DEB_NAME}"
    if [ "$DRY_RUN" -eq 1 ]; then
        say "  ${DIM}fetch${RESET}   ${CYAN}${DEB_URL}${RESET}"
        say "  ${DIM}install${RESET} ${CYAN}sudo dpkg -i ... || sudo apt-get install -f -y${RESET}"
        say ""
        ok "Simulation complete. No host modifications made."
        say ""
        exit 0
    fi
    TMP_DEB="$(mktemp /tmp/oogrep-deb.XXXXXX.deb)"
    story_line "Fetching ${DEB_NAME} from release channel…"
    if ! curl -fsSL "$DEB_URL" -o "$TMP_DEB"; then
        err "Failed to download Debian package from $DEB_URL"
        rm -f "$TMP_DEB"
        exit 1
    fi
    story_line "Installing Debian package…"
    sudo dpkg -i "$TMP_DEB" || sudo apt-get install -f -y
    rm -f "$TMP_DEB"
    ok "Installed oogrep Debian package."
    if command -v oogrep >/dev/null 2>&1; then
        ok "Living proof: ${GREEN}${BOLD}$(oogrep --version)${RESET}"
    fi
    say ""
    exit 0
fi

# --- DNF / RPM Installation ---
if [ "$INSTALL_DNF" -eq 1 ]; then
    step "Installing oogrep via DNF/rpm (${VERSION_PIN})"
    RPM_NAME="oogrep-${RAW_VERSION}-1.x86_64.rpm"
    RPM_URL="${GITHUB_URL}/releases/download/${VERSION_PIN}/${RPM_NAME}"
    if [ "$DRY_RUN" -eq 1 ]; then
        say "  ${DIM}install${RESET} ${CYAN}sudo dnf install -y ${RPM_URL}${RESET}"
        say ""
        ok "Simulation complete. No host modifications made."
        say ""
        exit 0
    fi
    story_line "Installing RPM package via dnf…"
    sudo dnf install -y "$RPM_URL" || sudo dnf install -y "${GITHUB_URL}/releases/download/${VERSION_PIN}/oogrep-${RAW_VERSION}-1.fc44.x86_64.rpm"
    ok "Installed oogrep RPM package."
    if command -v oogrep >/dev/null 2>&1; then
        ok "Living proof: ${GREEN}${BOLD}$(oogrep --version)${RESET}"
    fi
    say ""
    exit 0
fi

# --- Arch Linux / PKGBUILD Installation ---
if [ "$INSTALL_ARCH" -eq 1 ]; then
    step "Installing oogrep via PKGBUILD (${VERSION_PIN})"
    PKGBUILD_URL="https://raw.githubusercontent.com/${REPO}/${VERSION_PIN}/packaging/PKGBUILD"
    if [ "$DRY_RUN" -eq 1 ]; then
        say "  ${DIM}fetch${RESET}   ${CYAN}${PKGBUILD_URL}${RESET}"
        say "  ${DIM}build${RESET}   ${CYAN}makepkg -si --noconfirm${RESET}"
        say ""
        ok "Simulation complete. No host modifications made."
        say ""
        exit 0
    fi
    if ! command -v makepkg >/dev/null 2>&1; then
        err "makepkg not found. Arch Linux / pacman build tools are required for PKGBUILD installation."
        say "  Use standard installer instead: ${CYAN}curl -fsSL https://openooda-tools.github.io/oogrep/install.sh | bash${RESET}"
        exit 1
    fi
    TMP_ARCH="$(mktemp -d /tmp/oogrep-pkgbuild.XXXXXX)"
    story_line "Fetching PKGBUILD from repository…"
    if ! curl -fsSL "$PKGBUILD_URL" -o "${TMP_ARCH}/PKGBUILD"; then
        err "Failed to download PKGBUILD from $PKGBUILD_URL"
        rm -rf "$TMP_ARCH"
        exit 1
    fi
    story_line "Building and installing package via makepkg…"
    (cd "$TMP_ARCH" && makepkg -si --noconfirm)
    rm -rf "$TMP_ARCH"
    ok "Installed oogrep Arch package."
    if command -v oogrep >/dev/null 2>&1; then
        ok "Living proof: ${GREEN}${BOLD}$(oogrep --version)${RESET}"
    fi
    say ""
    exit 0
fi

# --- Phase 1: Identity & Attunement -------------------------------------------
step "[1/4]  Attuning host & kernel substrate"

OS="$(uname -s)"
if [ "$OS" != "Linux" ]; then
    warn "Non-Linux kernel detected: ${BOLD}${OS}${RESET}"
    story_line "oogrep is architected for native Linux. Continuing best-effort…"
fi

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64) TARGET_ARCH="x86_64" ;;
    aarch64|arm64) TARGET_ARCH="aarch64" ;;
    *)
        err "Unsupported hardware architecture: $ARCH (oogrep requires x86_64 or aarch64)"
        exit 1
        ;;
esac

OS_PRETTY="Linux"
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_PRETTY="${PRETTY_NAME:-Linux}"
fi

say "  ${DIM}os${RESET}       ${GREEN}${OS_PRETTY}${RESET}"
say "  ${DIM}arch${RESET}     ${GREEN}${TARGET_ARCH}${RESET} ${DIM}(${ARCH})${RESET}"
say "  ${DIM}kernel${RESET}   ${GREEN}$(uname -r)${RESET}"

if ! command -v curl >/dev/null 2>&1; then
    err "curl is required to retrieve sovereign release assets"
    exit 1
fi

HASH_CMD=""
if command -v sha256sum >/dev/null 2>&1; then
    HASH_CMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    HASH_CMD="shasum -a 256"
fi

if [ -z "$HASH_CMD" ]; then
    warn "No sha256 utility on PATH; cryptographic verification disabled."
else
    say "  ${DIM}crypto${RESET}   ${GREEN}${HASH_CMD}${RESET}"
fi

# Resolve destination directory
if [ -n "$CUSTOM_PREFIX" ]; then
    INSTALL_DIR="$CUSTOM_PREFIX"
elif [ "$(id -u)" -eq 0 ]; then
    INSTALL_DIR="/usr/local/bin"
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    INSTALL_DIR="/usr/local/bin"
else
    INSTALL_DIR="${HOME}/.local/bin"
fi
say "  ${DIM}target${RESET}   ${CYAN}${INSTALL_DIR}/oogrep${RESET}"
pause 0.3

# --- Phase 2: Resolving Release & Provenance ----------------------------------
step "[2/4]  Scrying release channels & provenance"

story_line "Contacting sovereign registry at ${GITHUB_URL}…"
LATEST_TAG=$(curl -sSL -H "Accept: application/vnd.github+json" "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep '"tag_name":' | head -1 | cut -d '"' -f 4 || echo "")
if [ -z "$LATEST_TAG" ]; then
    LATEST_TAG="$VERSION_PIN"
fi

ASSET_NAME="oogrep-linux-${TARGET_ARCH}"
ASSET_URL="${GITHUB_URL}/releases/download/${LATEST_TAG}/${ASSET_NAME}"
SHA_URL="${GITHUB_URL}/releases/download/${LATEST_TAG}/${ASSET_NAME}.sha256"

ok "Channel:  ${BOLD}${LATEST_TAG}${RESET} ${DIM}(canonical release)${RESET}"
ok "Artifact: ${BOLD}${ASSET_NAME}${RESET}"
pause 0.2

if [ "$DRY_RUN" -eq 1 ]; then
    step "[DRY RUN] Verification Plan"
    say "  ${DIM}fetch${RESET}   ${CYAN}${ASSET_URL}${RESET}"
    say "  ${DIM}verify${RESET}  ${CYAN}${SHA_URL}${RESET}"
    say "  ${DIM}deploy${RESET}  ${CYAN}${INSTALL_DIR}/oogrep${RESET}"
    say ""
    ok "Simulation complete. No host modifications made."
    say ""
    exit 0
fi

# --- Phase 3: Transmission & Cryptographic Seal -------------------------------
step "[3/4]  Transmuting & verifying cryptographic seal"

TMP_DIR="$(mktemp -d /tmp/oogrep-bootstrap.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

story_line "Streaming standalone binary artifact from release channel…"
curl -fsSL "$ASSET_URL" -o "${TMP_DIR}/${ASSET_NAME}" &
spin_while $! "Streaming ${ASSET_NAME}"
ok "Transmitted ${ASSET_NAME}"

story_line "Acquiring publisher's cryptographic SHA-256 seal…"
curl -fsSL "$SHA_URL" -o "${TMP_DIR}/${ASSET_NAME}.sha256" 2>/dev/null || true

if [ -f "${TMP_DIR}/${ASSET_NAME}.sha256" ] && [ -n "$HASH_CMD" ]; then
    EXPECTED_SHA=$(awk '{print $1}' "${TMP_DIR}/${ASSET_NAME}.sha256" | head -1)
    ACTUAL_SHA=$($HASH_CMD "${TMP_DIR}/${ASSET_NAME}" | awk '{print $1}')
    if [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
        err "Cryptographic seal violation! Download corrupted or tampered."
        say "  ${DIM}Expected:${RESET} ${YELLOW}${EXPECTED_SHA}${RESET}"
        say "  ${DIM}Actual:  ${RESET} ${YELLOW}${ACTUAL_SHA}${RESET}"
        exit 1
    fi
    ok "Cryptographic seal verified: ${DIM}${ACTUAL_SHA}${RESET}"
else
    warn "Checksum manifest unavailable; skipped seal verification."
fi
pause 0.3

if [ "$DO_VERIFY" -eq 1 ]; then
    if [ ! -f "${TMP_DIR}/${ASSET_NAME}.sha256" ] || [ -z "$HASH_CMD" ]; then
        err "Verification failed: Checksum manifest or hash utility unavailable."
        exit 1
    fi
    ok "Cryptographic verification succeeded. Exiting per --verify."
    say ""
    exit 0
fi

# --- Phase 4: Deploying oogrep ----------------------------------------------------
step "[4/4]  Awakening sovereign search tool"

if [ ! -d "$INSTALL_DIR" ]; then
    mkdir -p "$INSTALL_DIR" 2>/dev/null || sudo mkdir -p "$INSTALL_DIR"
fi

chmod +x "${TMP_DIR}/${ASSET_NAME}"

story_line "Placing binary into ${INSTALL_DIR}…"
if [ -w "$INSTALL_DIR" ]; then
    mv "${TMP_DIR}/${ASSET_NAME}" "${INSTALL_DIR}/oogrep"
else
    sudo mv "${TMP_DIR}/${ASSET_NAME}" "${INSTALL_DIR}/oogrep"
fi
ok "Binary situated at ${BOLD}${INSTALL_DIR}/oogrep${RESET}"

story_line "Equipping clean uninstaller helper at ${INSTALL_DIR}/oogrep-uninstall…"
cat << 'EOF_UNINSTALL' > "${TMP_DIR}/oogrep-uninstall"
#!/bin/sh
# ==============================================================================
# oogrep-uninstall - Clean uninstaller for oogrep
# ==============================================================================
set -eu

DRY_RUN=0
ASSUME_YES=0
CUSTOM_PREFIX=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        -y|--yes) ASSUME_YES=1; shift ;;
        --prefix) CUSTOM_PREFIX="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: oogrep-uninstall [options]"
            echo "Options:"
            echo "  --prefix <dir>   Target binary directory to inspect (e.g. /opt/bin)"
            echo "  --dry-run        Simulate removal without modifying host"
            echo "  -y, --yes        Non-interactive mode (auto-confirm removal)"
            echo "  -h, --help       Display this manual"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [ "$ASSUME_YES" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    CONFIRMED=0
    if [ -t 0 ]; then
        printf "Are you sure you want to remove oogrep from this system? [y/N] "
        read -r ANSWER
        case "$ANSWER" in [yY]|[yY][eE][sS]) CONFIRMED=1 ;; esac
    elif [ -e /dev/tty ]; then
        printf "Are you sure you want to remove oogrep from this system? [y/N] " </dev/tty
        read -r ANSWER </dev/tty
        case "$ANSWER" in [yY]|[yY][eE][sS]) CONFIRMED=1 ;; esac
    else
        CONFIRMED=1
    fi
    if [ "$CONFIRMED" -eq 0 ]; then
        echo "Uninstallation cancelled by user."
        exit 0
    fi
fi

FOUND=0

# 1. Package Managers
if command -v dpkg >/dev/null 2>&1 && dpkg -s oogrep >/dev/null 2>&1; then
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] Would remove Debian package: oogrep"
        FOUND=1
    else
        if sudo apt-get remove -y oogrep 2>/dev/null || sudo dpkg -r oogrep 2>/dev/null; then
            echo "Banished Debian package: oogrep"
            FOUND=1
        fi
    fi
elif command -v rpm >/dev/null 2>&1 && rpm -q oogrep >/dev/null 2>&1; then
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] Would remove RPM package: oogrep"
        FOUND=1
    else
        if sudo dnf remove -y oogrep 2>/dev/null || sudo rpm -e oogrep 2>/dev/null; then
            echo "Banished RPM package: oogrep"
            FOUND=1
        fi
    fi
elif command -v pacman >/dev/null 2>&1; then
    if pacman -Qi oogrep >/dev/null 2>&1; then
        if [ "$DRY_RUN" -eq 1 ]; then echo "[dry-run] Would remove Arch package: oogrep"; FOUND=1; else sudo pacman -R --noconfirm oogrep 2>/dev/null && echo "Banished Arch package: oogrep" && FOUND=1; fi
    fi
    if pacman -Qi oogrep-bin >/dev/null 2>&1; then
        if [ "$DRY_RUN" -eq 1 ]; then echo "[dry-run] Would remove Arch package: oogrep-bin"; FOUND=1; else sudo pacman -R --noconfirm oogrep-bin 2>/dev/null && echo "Banished Arch package: oogrep-bin" && FOUND=1; fi
    fi
fi

# 2. Binaries and Uninstaller
SEARCH_DIRS="/usr/local/bin ${HOME}/.local/bin ${HOME}/.openooda/bin /usr/bin /bin"
if [ -n "$CUSTOM_PREFIX" ]; then SEARCH_DIRS="${CUSTOM_PREFIX} ${SEARCH_DIRS}"; fi

for d in $SEARCH_DIRS; do
    for file in "${d}/oogrep" "${d}/oogrep-uninstall"; do
        if [ -f "$file" ] || [ -L "$file" ]; then
            if [ "$DRY_RUN" -eq 1 ]; then
                echo "[dry-run] Would remove $file"
                FOUND=1
            else
                if rm -f "$file" 2>/dev/null || sudo rm -f "$file" 2>/dev/null; then
                    echo "Removed $file"
                    FOUND=1
                fi
            fi
        fi
    done
done

# 3. Integrations, Man Pages, and Caches
for f in "/etc/bash_completion.d/oogrep" "/usr/local/share/zsh/site-functions/_oogrep" "${HOME}/.local/share/zsh/site-functions/_oogrep" "${HOME}/.config/fish/completions/oogrep.fish" "/usr/local/share/man/man1/oogrep.1" "/usr/local/share/man/man1/oogrep.1.gz" "${HOME}/.local/share/man/man1/oogrep.1" "${HOME}/.local/share/man/man1/oogrep.1.gz"; do
    if [ -f "$f" ] || [ -L "$f" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then echo "[dry-run] Would remove $f"; FOUND=1; else rm -f "$f" 2>/dev/null || sudo rm -f "$f" 2>/dev/null || true; echo "Removed $f"; FOUND=1; fi
    fi
done

for c in "${HOME}/.cache/oogrep" "${HOME}/.config/oogrep"; do
    if [ -d "$c" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then echo "[dry-run] Would remove directory $c"; FOUND=1; else rm -rf "$c" 2>/dev/null || true; echo "Removed directory $c"; FOUND=1; fi
    fi
done

if [ "$FOUND" -eq 0 ]; then
    echo "No oogrep installations, packages, or artifacts detected."
else
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "Dry run complete. No files were removed."
    else
        echo "oogrep has been cleanly relinquished from this host."
    fi
fi
EOF_UNINSTALL

chmod +x "${TMP_DIR}/oogrep-uninstall"
if [ -w "$INSTALL_DIR" ]; then
    mv "${TMP_DIR}/oogrep-uninstall" "${INSTALL_DIR}/oogrep-uninstall"
else
    sudo mv "${TMP_DIR}/oogrep-uninstall" "${INSTALL_DIR}/oogrep-uninstall"
fi
ok "Clean uninstaller situated at ${BOLD}${INSTALL_DIR}/oogrep-uninstall${RESET}"

if "${INSTALL_DIR}/oogrep" --version >/dev/null 2>&1; then
    VER_PROVE=$("${INSTALL_DIR}/oogrep" --version)
    ok "Living proof: ${GREEN}${BOLD}${VER_PROVE}${RESET}"
else
    warn "Verification probe non-responsive."
fi

# PATH Inspection
PATH_OK=0
case ":$PATH:" in
    *:"$INSTALL_DIR":*) PATH_OK=1 ;;
esac

victory_banner

if [ "$PATH_OK" -eq 0 ]; then
    warn "The directory ${BOLD}${INSTALL_DIR}${RESET} is not in your current \$PATH."
    say ""
    say "  To enable ${BOLD}oogrep${RESET} across your environment, add to ${BOLD}~/.bashrc${RESET} or ${BOLD}~/.zshrc${RESET}:"
    say "    ${CYAN}export PATH=\"${INSTALL_DIR}:\$PATH\"${RESET}"
    say ""
fi

say "  ${BOLD}Try it right now:${RESET}"
say "    ${AMBER}${BOLD}${INSTALL_DIR}/oogrep --help${RESET}"
say "    ${AMBER}${BOLD}${INSTALL_DIR}/oogrep -n \"TODO\" .${RESET}"
say ""
say "  ${BOLD}Machine-readable output for scripts and agents:${RESET}"
say "    ${DIM}${INSTALL_DIR}/oogrep --json \"TODO\" .${RESET}"
say ""
say "  ${BOLD}Clean uninstaller:${RESET}"
say "    ${DIM}${INSTALL_DIR}/oogrep-uninstall (or curl -fsSL https://openooda-tools.github.io/oogrep/uninstall.sh | bash)${RESET}"
say ""
