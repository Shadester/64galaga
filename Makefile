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
TARGET = $(BUILD_DIR)/galaga.prg

# Source files
SOURCES = $(SRC_DIR)/main.asm

# Default target
all: $(TARGET)

# Build the program
$(TARGET): $(SOURCES) | $(BUILD_DIR)
	@echo "Assembling $(TARGET)..."
	$(ASM) $(ASMFLAGS) $(TARGET) $(SRC_DIR)/main.asm
	@echo "Build complete!"

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Run in emulator with WASD controls configured
run: $(TARGET)
	@echo "Starting VICE emulator with WASD controls..."
	@echo ""
	@echo "Controls:"
	@echo "  W = Up"
	@echo "  A = Left"
	@echo "  S = Down"
	@echo "  D = Right"
	@echo "  Space = Fire"
	@echo ""
	$(EMU) $(EMUFLAGS) -config .vice/vicerc -autostart $(TARGET)

# Clean build artifacts
clean:
	@echo "Cleaning build directory..."
	rm -rf $(BUILD_DIR)/*

# Rebuild from scratch
rebuild: clean all

.PHONY: all run clean rebuild
