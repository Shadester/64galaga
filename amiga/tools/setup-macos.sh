#!/usr/bin/env bash
# Install the tools needed to build and run the game on macOS: the 68000 cross compiler (m68k-elf-gcc, m68k-elf-binutils),
# the FS-UAE emulator (it has the AROS replacement ROM inside: no Kickstart needed) and Pillow for tools/*.py.
# The tests also need Playwright: pip install playwright && playwright install chromium (they run the game in vAmigaWeb).
set -euo pipefail

if ! command -v brew >/dev/null; then
    echo "Homebrew not found. Install it from https://brew.sh, then re-run." >&2
    exit 1
fi

for pkg in m68k-elf-gcc m68k-elf-binutils python3 pillow; do
    brew list --formula "$pkg" >/dev/null 2>&1 || brew install "$pkg"
done
[ -d /Applications/FS-UAE.app ] || brew install --cask fs-uae-emulator

command -v make >/dev/null || xcode-select --install

echo
for tool in m68k-elf-gcc m68k-elf-as m68k-elf-objcopy python3 make; do
    printf '%-18s %s\n' "$tool" "$(command -v "$tool" || echo MISSING)"
done
ls -d /Applications/FS-UAE.app 2>/dev/null || echo "FS-UAE.app MISSING"
