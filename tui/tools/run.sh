#!/bin/sh
# Build and run the game in this terminal (the window must be at least 80 x 27 cells; 160 x 52 shows the biggest picture).
# Arguments go to the program: --autoplay, --stage N, --god, --no-save, --help
cd "$(dirname "$0")/.." || exit 1
exec cargo run --release -q -- "$@"
