#!/bin/sh
# Build and run the portrait version in the Gearlynx window (the header tells the emulator to turn the picture). Same as run.sh.
cd "$(dirname "$0")/.." || exit 1
BUILD=build/portrait MAKEARGS=PORTRAIT=1 exec tools/run.sh
