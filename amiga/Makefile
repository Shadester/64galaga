# Amiga Galaga: m68k-elf-gcc (Homebrew: m68k-elf-gcc m68k-elf-binutils) -> raw image -> ADF
CC = m68k-elf-gcc
EXTRA_CFLAGS =
CFLAGS = -m68000 -Os -ffreestanding -fno-pic -Wall -Wextra -Wno-unused-parameter -I ../psp -I src -isystem src/inc $(EXTRA_CFLAGS)
BUILD = build
OBJ = $(BUILD)/hw.o $(BUILD)/main.o $(BUILD)/video.o $(BUILD)/audio.o $(BUILD)/game.o $(BUILD)/libc.o

all: $(BUILD)/galaga.adf

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.o: src/%.c $(wildcard src/*.h) ../psp/game.c ../psp/game.h | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

# the rules are the hot code: speed before size
$(BUILD)/game.o: CFLAGS += -O2

$(BUILD)/%.o: src/%.s | $(BUILD)
	m68k-elf-as -m68000 --register-prefix-optional -o $@ $<

$(BUILD)/game.elf: $(OBJ) link.ld
	$(CC) -m68000 -nostdlib -T link.ld -o $@ $(OBJ) -lgcc -Wl,-Map=$(BUILD)/game.map

$(BUILD)/game.bin: $(BUILD)/game.elf
	m68k-elf-objcopy -O binary $< $@

$(BUILD)/boot.bin: $(BUILD)/boot.o
	m68k-elf-objcopy -O binary -j .text $< $@

$(BUILD)/galaga.adf: $(BUILD)/boot.bin $(BUILD)/game.bin tools/make_adf.py
	python3 tools/make_adf.py $(BUILD)/boot.bin $(BUILD)/game.bin $@

clean:
	rm -rf $(BUILD)

.PHONY: all clean

# docs/galaga.adz: the ADF, gzipped (vAmigaWeb plays it from a link, like the C64 version in vc64web)
web: $(BUILD)/galaga.adf
	python3 -c "import gzip,sys; open('docs/galaga.adz','wb').write(gzip.compress(open('$(BUILD)/galaga.adf','rb').read(), 9, mtime=0))"
	@ls -l docs/galaga.adz

.PHONY: web
