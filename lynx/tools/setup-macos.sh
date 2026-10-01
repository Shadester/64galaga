#!/usr/bin/env bash
# Install the tools needed to build and run the game on macOS: cc65 (ca65/ld65), Gearlynx, Pillow.
# The Lynx boot ROM is copyrighted: put your own dump at lynx/lynxboot.img (512 bytes, git-ignored).
set -euo pipefail

if ! command -v brew >/dev/null; then
    echo "Homebrew not found. Install it from https://brew.sh, then re-run." >&2
    exit 1
fi

# cc65: ca65/ld65, gearlynx: emulator with a headless MCP server (tests), pillow: tools/*.py
for pkg in cc65 python3 pillow; do
    brew list --formula "$pkg" >/dev/null 2>&1 || brew install "$pkg"
done
ls -d /Applications/Gearlynx.app 2>/dev/null || echo "Gearlynx.app MISSING"
brew list --cask gearlynx >/dev/null 2>&1 || brew install --cask drhelius/geardome/gearlynx

command -v make >/dev/null || xcode-select --install

BIOS=$(dirname "$0")/../lynxboot.img
if [ "$(md5 -q "$BIOS" 2>/dev/null)" != fcd403db69f54290b51035d82f835e7b ]; then
    echo "lynx/lynxboot.img missing or not the original boot ROM (md5 fcd403db69f54290b51035d82f835e7b)." >&2
fi

echo
for tool in ca65 ld65 python3 make; do
    printf '%-9s %s\n' "$tool" "$(command -v "$tool" || echo MISSING)"
done
ls -d /Applications/Gearlynx.app 2>/dev/null || echo "Gearlynx.app MISSING"
