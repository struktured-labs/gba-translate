# GB/GBA Translation FPGA Core - Makefile
#
# Targets:
#   make test          - Run all testbenches
#   make test-hash     - Run tile hash generator test
#   make test-snooper  - Run VRAM snooper test
#   make vectors       - Regenerate test vectors
#   make clean         - Clean build artifacts
#   make lint          - Run Verilator lint checks

# Tools
IVERILOG = iverilog
VVP = vvp
VERILATOR = verilator
PYTHON = uv run python

# Directories
RTL_DIR = src/rtl
TB_DIR = $(RTL_DIR)/tb
CORE_DIR = $(RTL_DIR)/core
MEM_DIR = $(RTL_DIR)/memory
VECTOR_DIR = tests/vectors
BUILD_DIR = build

# Source files
CORE_SRCS = \
    $(CORE_DIR)/tile_hash_generator.sv \
    $(CORE_DIR)/vram_snooper.sv \
    $(CORE_DIR)/hash_lookup_table.sv \
    $(CORE_DIR)/caption_renderer.sv \
    $(CORE_DIR)/alpha_blender.sv \
    $(CORE_DIR)/replace_mode_ctrl.sv \
    $(CORE_DIR)/translation_overlay_top.sv

MEM_SRCS = \
    $(MEM_DIR)/font_rom.sv

ALL_SRCS = $(CORE_SRCS) $(MEM_SRCS)

# Testbench files
TB_HASH = $(TB_DIR)/tb_tile_hash_generator.sv
TB_SNOOPER = $(TB_DIR)/tb_vram_snooper.sv
TB_LOOKUP = $(TB_DIR)/tb_hash_lookup_table.sv

# Include paths
INCLUDES = -I$(VECTOR_DIR) -I$(TB_DIR) -I$(CORE_DIR) -I$(MEM_DIR)

# Iverilog flags
IVFLAGS = -g2012 -Wall $(INCLUDES)

# Verilator flags
VFLAGS = --lint-only -Wall --timing $(INCLUDES)

# Default target
.PHONY: all
all: test

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Generate test vectors
.PHONY: vectors
vectors:
	$(PYTHON) src/tools/test_vectors.py --output $(VECTOR_DIR)

# Ensure vectors exist
$(VECTOR_DIR)/test_vectors.svh: src/tools/test_vectors.py
	$(PYTHON) src/tools/test_vectors.py --output $(VECTOR_DIR)

#------------------------------------------------------------------------------
# Tile Hash Generator Tests
#------------------------------------------------------------------------------

$(BUILD_DIR)/tb_tile_hash_generator: $(TB_HASH) $(CORE_DIR)/tile_hash_generator.sv $(VECTOR_DIR)/test_vectors.svh | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -o $@ $(CORE_DIR)/tile_hash_generator.sv $(TB_HASH)

.PHONY: test-hash
test-hash: $(BUILD_DIR)/tb_tile_hash_generator
	@echo "========================================="
	@echo "Running Tile Hash Generator Test"
	@echo "========================================="
	$(VVP) $(BUILD_DIR)/tb_tile_hash_generator

.PHONY: test-hash-vcd
test-hash-vcd: $(BUILD_DIR)/tb_tile_hash_generator
	$(VVP) $(BUILD_DIR)/tb_tile_hash_generator +vcd
	@echo "Waveform saved to tb_tile_hash_generator.vcd"

#------------------------------------------------------------------------------
# VRAM Snooper Tests
#------------------------------------------------------------------------------

$(BUILD_DIR)/tb_vram_snooper: $(TB_SNOOPER) $(CORE_DIR)/vram_snooper.sv | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -o $@ $(CORE_DIR)/vram_snooper.sv $(TB_SNOOPER)

.PHONY: test-snooper
test-snooper: $(BUILD_DIR)/tb_vram_snooper
	@echo "========================================="
	@echo "Running VRAM Snooper Test"
	@echo "========================================="
	$(VVP) $(BUILD_DIR)/tb_vram_snooper

#------------------------------------------------------------------------------
# Hash Lookup Table Tests
#------------------------------------------------------------------------------

$(BUILD_DIR)/tb_hash_lookup_table: $(TB_LOOKUP) $(CORE_DIR)/hash_lookup_table.sv | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -o $@ $(CORE_DIR)/hash_lookup_table.sv $(TB_LOOKUP)

.PHONY: test-lookup
test-lookup: $(BUILD_DIR)/tb_hash_lookup_table
	@echo "========================================="
	@echo "Running Hash Lookup Table Test"
	@echo "========================================="
	$(VVP) $(BUILD_DIR)/tb_hash_lookup_table

#------------------------------------------------------------------------------
# Run All Tests
#------------------------------------------------------------------------------

.PHONY: test
test: test-hash test-snooper
	@echo ""
	@echo "========================================="
	@echo "All tests completed"
	@echo "========================================="

#------------------------------------------------------------------------------
# Lint Check (Verilator)
#------------------------------------------------------------------------------

.PHONY: lint
lint:
	@echo "Running Verilator lint on all source files..."
	$(VERILATOR) $(VFLAGS) $(ALL_SRCS) --top-module translation_overlay_top

.PHONY: lint-hash
lint-hash:
	$(VERILATOR) $(VFLAGS) $(CORE_DIR)/tile_hash_generator.sv --top-module tile_hash_generator

.PHONY: lint-snooper
lint-snooper:
	$(VERILATOR) $(VFLAGS) $(CORE_DIR)/vram_snooper.sv --top-module vram_snooper

#------------------------------------------------------------------------------
# Clean
#------------------------------------------------------------------------------

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
	rm -f *.vcd
	rm -f *.log

.PHONY: clean-vectors
clean-vectors:
	rm -rf $(VECTOR_DIR)

.PHONY: distclean
distclean: clean clean-vectors

#------------------------------------------------------------------------------
# Help
#------------------------------------------------------------------------------

.PHONY: help
help:
	@echo "GB/GBA Translation FPGA Core - Build Targets"
	@echo ""
	@echo "Testing:"
	@echo "  make test          - Run all testbenches"
	@echo "  make test-hash     - Run tile hash generator test"
	@echo "  make test-hash-vcd - Run with VCD waveform output"
	@echo "  make test-snooper  - Run VRAM snooper test"
	@echo "  make test-lookup   - Run hash lookup table test"
	@echo ""
	@echo "Linting:"
	@echo "  make lint          - Run Verilator lint on all sources"
	@echo "  make lint-hash     - Lint tile_hash_generator only"
	@echo ""
	@echo "Utilities:"
	@echo "  make vectors       - Regenerate test vectors"
	@echo "  make clean         - Remove build artifacts"
	@echo "  make help          - Show this help"
