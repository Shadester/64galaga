#!/usr/bin/env bash
# Install the tools needed to build and run the game on macOS: PSPSDK (pspdev release), PPSSPP,
# ffmpeg (GIF recording) and Pillow (logo.h). PSPSDK goes to $PSPDEV (default ~/pspdev).
set -euo pipefail

if ! command -v brew >/dev/null; then
    echo "Homebrew not found. Install it from https://brew.sh, then re-run." >&2
    exit 1
fi

PSPDEV=${PSPDEV:-$HOME/pspdev}
case $(uname -m) in
    arm64) asset=pspdev-macos-latest-arm64.tar.gz ;;
    *)     asset=pspdev-macos-15-intel-x86_64.tar.gz ;;
esac

if [ ! -x "$PSPDEV/bin/psp-config" ]; then
    mkdir -p "$PSPDEV"
    curl -fL "https://github.com/pspdev/pspdev/releases/latest/download/$asset" |
        tar xz --strip-components=1 -C "$PSPDEV"
fi

# ppsspp-emulator: PPSSPPSDL.app, ffmpeg: tools/run_shots.sh GIF, pillow: tools/logo2h.py
[ -d /Applications/PPSSPPSDL.app ] || brew install --cask ppsspp-emulator
for pkg in ffmpeg python3 pillow; do
    brew list --formula "$pkg" >/dev/null 2>&1 || brew install "$pkg"
done

command -v make >/dev/null || xcode-select --install

echo
echo "Add to your shell profile:"
echo "  export PSPDEV=$PSPDEV"
echo "  export PATH=\$PATH:\$PSPDEV/bin"
echo
for tool in psp-config psp-gcc make ffmpeg; do
    printf '%-10s %s\n' "$tool" "$(PATH=$PATH:$PSPDEV/bin command -v "$tool" || echo MISSING)"
done
ls -d /Applications/PPSSPPSDL.app 2>/dev/null || echo "PPSSPPSDL.app MISSING"
