# Atari Lynx Galaga: ca65 / ld65 (cc65 suite)
CA65 = ca65 --cpu 65SC02 -I src
LD65 = ld65
SRC = $(wildcard src/*.s)
BUILD ?= build
OBJ = $(SRC:src/%.s=$(BUILD)/%.o)
TARGET = $(BUILD)/galaga.lnx
BIOS ?= lynxboot.img

all: $(TARGET)

$(BUILD)/%.o: src/%.s $(wildcard src/*.inc src/game/*.s) | $(BUILD)
	$(CA65) $(CAFLAGS) -o $@ $<

$(TARGET): $(OBJ) lynx.cfg
	$(LD65) -C lynx.cfg -m $(BUILD)/galaga.map -Ln $(BUILD)/galaga.lbl -o $@ $(OBJ) lynx.lib

$(BUILD):
	mkdir -p $(BUILD)

run: $(TARGET)
	tools/run.sh

clean:
	rm -rf build

.PHONY: all run clean
