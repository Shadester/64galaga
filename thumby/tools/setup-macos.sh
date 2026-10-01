#!/usr/bin/env bash
# Build the Thumby Color game engine for the desktop (TinyCircuits' MicroPython fork, Unix port, SDL2 window),
# so the game runs and is tested on the Mac without a device. Result: build/mp-thumby/ports/unix/build-standard/micropython
# The engine is made for Linux: on macOS three things need a flag (see the make line below).
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v brew >/dev/null; then
    echo "Homebrew not found. Install it from https://brew.sh, then re-run." >&2
    exit 1
fi
for pkg in sdl2 libffi pkgconf; do
    brew list --formula "$pkg" >/dev/null 2>&1 || brew install "$pkg"
done
# pillow: tools/gen_assets.py, tests; mpremote: tools/install.sh (copies the game to a real Thumby Color)
python3 -c "import PIL" 2>/dev/null || brew install pillow
command -v mpremote >/dev/null || brew install mpremote

mkdir -p build
[ -d build/mp-thumby ] || git clone --branch engine --depth 1 https://github.com/TinyCircuits/micropython.git build/mp-thumby
cd build/mp-thumby
git submodule update --init --depth 1 TinyCircuits-Tiny-Game-Engine
(cd TinyCircuits-Tiny-Game-Engine && git submodule update --init --recursive --depth 1)

# -Wno-error: newer clang warns about code that MicroPython compiles with -Werror
make -C mpy-cross -j8 CFLAGS_EXTRA="-Wno-error"
cd ports/unix
make submodules
# -D__unix__=1: the engine tests __unix__ (macOS defines only __APPLE__); the SDL flags: Homebrew keeps SDL2 outside the default paths
make -j8 USER_C_MODULES=../../TinyCircuits-Tiny-Game-Engine \
    CFLAGS_EXTRA="-D__unix__=1 -I/opt/homebrew/include -Wno-error" LDFLAGS_EXTRA="-L/opt/homebrew/lib -lSDL2"

echo
ls -l build-standard/micropython
