# Atari Lynx Galaga: ca65 / ld65 (cc65 suite)
CA65 = ca65 --cpu 65SC02 -I src
LD65 = ld65
SRC = $(wildcard src/*.s)
OBJ = $(SRC:src/%.s=build/%.o)
TARGET = build/galaga.lnx
BIOS ?= lynxboot.img

all: $(TARGET)

build/%.o: src/%.s $(wildcard src/*.inc) | build
	$(CA65) $(CAFLAGS) -o $@ $<

$(TARGET): $(OBJ) lynx.cfg
	$(LD65) -C lynx.cfg -m build/galaga.map -Ln build/galaga.lbl -o $@ $(OBJ) lynx.lib

build:
	mkdir -p build

run: $(TARGET)
	tools/run.sh

clean:
	rm -rf build

.PHONY: all run clean
