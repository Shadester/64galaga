# Commodore 64 Galaga Clone - Makefile

# Assembler
ASM = acme
ASMFLAGS = -f cbm -o

# Emulator
EMU = x64sc
EMUFLAGS = -VICIIdsize -VICIIfilter 0

# Directories
SRC_DIR = src
BUILD_DIR = build
ASSETS_DIR = assets

# Target
RAW = $(BUILD_DIR)/galaga-raw.prg
TARGET = $(BUILD_DIR)/galaga.prg
DISK = $(BUILD_DIR)/galaga.d64

# Source files
SOURCES = $(wildcard $(SRC_DIR)/*.asm)

# Default target
all: $(TARGET) $(DISK)

# Assemble, then compress with exomizer (a self-extracting PRG: SYS starts it)
$(RAW): $(SOURCES) | $(BUILD_DIR)
	@echo "Assembling $(RAW)..."
	$(ASM) $(ASMFLAGS) $(RAW) $(SRC_DIR)/main.asm

$(TARGET): $(RAW)
	exomizer sfx sys -n -o $(TARGET) $(RAW) >/dev/null
	@echo "Build complete!"

# Disk image (c1541 ships with VICE)
$(DISK): $(TARGET)
	c1541 -format galaga,01 d64 $(DISK) -write $(TARGET) galaga >/dev/null
	@echo "Disk image: $(DISK)"

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Run in emulator with WASD controls configured
run: $(DISK)
	@echo "Starting VICE emulator with WASD controls..."
	@echo ""
	@echo "Controls:"
	@echo "  W = Up"
	@echo "  A = Left"
	@echo "  S = Down"
	@echo "  D = Right"
	@echo "  Space = Fire"
	@echo ""
	$(EMU) $(EMUFLAGS) -autostart $(DISK)

# Screenshot regression tests (see tests/run.sh)
test:
	@tests/run.sh

test-update:
	@tests/run.sh --update

# Clean build artifacts
clean:
	@echo "Cleaning build directory..."
	rm -rf $(BUILD_DIR)/*

# Rebuild from scratch
rebuild: clean all

.PHONY: all run test test-update clean rebuild
