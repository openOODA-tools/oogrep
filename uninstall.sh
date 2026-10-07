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
            echo "Usage: uninstall.sh [options]"
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
