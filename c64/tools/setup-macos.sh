#!/usr/bin/env bash
# Install the tools needed to build and run the game on macOS.
set -euo pipefail

if ! command -v brew >/dev/null; then
    echo "Homebrew not found. Install it from https://brew.sh, then re-run." >&2
    exit 1
fi

# acme: assembler, vice: x64sc emulator, exomizer: PRG compressor,
# pillow: screenshot compare in tests/ and the path preview in tools/gen_paths.py
# (make is in Xcode CLT)
for pkg in acme vice exomizer python3 pillow; do
    brew list --formula "$pkg" >/dev/null 2>&1 || brew install "$pkg"
done

command -v make >/dev/null || xcode-select --install

echo
for tool in acme x64sc exomizer c1541 python3 make; do
    printf '%-8s %s\n' "$tool" "$(command -v "$tool" || echo MISSING)"
done
