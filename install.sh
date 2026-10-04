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
#   --dry-run        Simulate installation without touching the filesystem
#   --verify         Perform strict cryptographic SHA-256 integrity verification
#   --uninstall      Remove oogrep binary from standard system paths
#   -h, --help       Show this help message
# ==============================================================================

set -eu

REPO="openOODA-tools/oogrep"
GITHUB_URL="https://github.com/${REPO}"
CANONICAL_URL="https://openooda-tools.github.io/oogrep"
VERSION_PIN="v0.2.0"

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
        ║      ██████╗  ██████╗ ███████╗██╗  ██╗                   ║
        ║     ██╔═══██╗██╔═══██╗██╔════╝██║  ██║                   ║
        ║     ██║   ██║██║   ██║███████╗███████║                   ║
        ║     ██║   ██║██║   ██║╚════██║██╔══██║                   ║
        ║     ╚██████╔╝╚██████╔╝███████║██║  ██║                   ║
        ║      ╚═════╝  ╚═════╝ ╚══════╝╚═╝  ╚═╝                   ║
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
CUSTOM_PREFIX=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --uninstall) DO_UNINSTALL=1; shift ;;
        --verify) DO_VERIFY=1; shift ;;
        --prefix) CUSTOM_PREFIX="$2"; shift 2 ;;
        -h|--help)
            banner
            say "  ${BOLD}Usage:${RESET} curl -fsSL .../install.sh | bash [options]"
            say ""
            say "  ${BOLD}Options:${RESET}"
            say "    ${CYAN}--prefix <dir>${RESET}   Target binary directory (default: /usr/local/bin or ~/.local/bin)"
            say "    ${CYAN}--dry-run${RESET}        Simulate deployment without modifying host"
            say "    ${CYAN}--verify${RESET}         Verify cryptographic SHA-256 seal and exit"
            say "    ${CYAN}--uninstall${RESET}      Cleanly remove oogrep binary from system"
            say "    ${CYAN}-h, --help${RESET}       Display this manual"
            say ""
            exit 0
            ;;
        *) err "Unknown flag: $1"; exit 1 ;;
    esac
done

banner
story_line "Attuning your environment to the openOODA sovereign shell…"
pause 0.3

# --- Uninstall Path -----------------------------------------------------------
if [ "$DO_UNINSTALL" -eq 1 ]; then
    step "Relinquishing oogrep"
    FOUND=0
    for p in /usr/local/bin/oogrep "${HOME}/.local/bin/oogrep" "${HOME}/.openooda/bin/oogrep"; do
        if [ -f "$p" ]; then
            if [ "$DRY_RUN" -eq 1 ]; then
                dim "Would remove $p"
            else
                rm -f "$p" 2>/dev/null || sudo rm -f "$p"
                ok "Banished ${BOLD}$p${RESET}"
            fi
            FOUND=1
        fi
    done
    if [ "$FOUND" -eq 0 ]; then
        warn "No existing oogrep binary detected in standard search paths."
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

# --- Phase 4: Deploying oogrep ----------------------------------------------------
step "[4/4]  Awakening sovereign shell"

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

say "  ${BOLD}Enter your sovereign shell right now:${RESET}"
say "    ${AMBER}${BOLD}${INSTALL_DIR}/oogrep${RESET}"
say ""
say "  ${BOLD}Make oogrep your default login shell:${RESET}"
say "    ${DIM}echo \"${INSTALL_DIR}/oogrep\" | sudo tee -a /etc/shells${RESET}"
say "    ${BOLD}chsh -s \"${INSTALL_DIR}/oogrep\"${RESET}"
say ""
