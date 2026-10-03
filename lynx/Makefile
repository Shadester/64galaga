# Atari Lynx Galaga: ca65 / ld65 (cc65 suite)
LD65 = ld65
SRC = $(wildcard src/*.s)
INC = -I src
# The portrait ROM (make PORTRAIT=1, or -D PORTRAIT=1 in CAFLAGS): the art, the font and the title picture are the turned ones of src/portrait/
ifneq (,$(or $(PORTRAIT),$(findstring PORTRAIT,$(CAFLAGS))))
CAFLAGS += $(if $(PORTRAIT),-D PORTRAIT=1)
SRC := $(filter-out src/art.s src/font.s src/title.s,$(SRC)) $(wildcard src/portrait/*.s)
INC = -I src/portrait -I src
endif
CA65 = ca65 --cpu 65SC02 $(INC)
BUILD ?= build
OBJ = $(SRC:src/%.s=$(BUILD)/%.o)
TARGET = $(BUILD)/galaga.lnx
BIOS ?= lynxboot.img

all: $(TARGET)

$(BUILD)/%.o: src/%.s $(wildcard src/*.inc src/game/*.s src/portrait/*.inc) | $(BUILD)
	@mkdir -p $(dir $@)
	$(CA65) $(CAFLAGS) -o $@ $<

$(TARGET): $(OBJ) lynx.cfg
	$(LD65) -C lynx.cfg -m $(BUILD)/galaga.map -Ln $(BUILD)/galaga.lbl -o $@ $(OBJ) lynx.lib

$(BUILD):
	mkdir -p $(BUILD)

run: $(TARGET)
	tools/run.sh

run-portrait:
	tools/run_portrait.sh

clean:
	rm -rf build

.PHONY: all run run-portrait clean
