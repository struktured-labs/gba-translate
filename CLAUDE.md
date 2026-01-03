# Claude Code Instructions for gba-translate

## Project Overview

FPGA core for real-time Japanese text translation on Game Boy/GBA games. Multi-platform support:
- **Analogue Pocket** (openFPGA) - Play real Japanese cartridges with translation
- **MiSTer FPGA** - ROM-based with easier development/debugging

## Architecture

```
vram_snooper → tile_hash_generator → hash_lookup_table → translation_engine
                                                              ↓
                                            caption_renderer / replace_mode_ctrl
```

## Development Commands

```bash
# Run all tests (29 tests across 4 suites)
make test

# Individual test suites
make test-hash        # Tile hash generator (8 tests)
make test-snooper     # VRAM snooper (4 tests)
make test-lookup      # Hash lookup table (12 tests)
make test-integration # End-to-end pipeline (5 tests)

# Lint with Verilator
make lint

# Generate test vectors
make vectors

# Clean build artifacts
make clean
```

## Directory Structure

```
src/rtl/
├── core/              # Shared translation logic (platform-agnostic)
├── memory/            # Font ROM, shared memory modules
├── platform/
│   ├── analogue/      # Analogue Pocket wrapper (stub)
│   └── mister/        # MiSTer wrapper (stub)
└── tb/                # Testbenches
```

## Key Files

| File | Purpose |
|------|---------|
| `src/rtl/core/vram_snooper.sv` | Monitors VRAM writes, captures 8x8 tiles |
| `src/rtl/core/tile_hash_generator.sv` | CRC-16-CCITT hash computation |
| `src/rtl/core/hash_lookup_table.sv` | Bloom filter + hash table lookup |
| `src/rtl/core/caption_renderer.sv` | Text overlay rendering |
| `src/rtl/core/replace_mode_ctrl.sv` | Tile substitution logic |
| `src/rtl/core/translation_overlay_top.sv` | Top-level integration |
| `src/rtl/platform/analogue/pocket_top.sv` | Analogue Pocket wrapper (stub) |
| `src/rtl/platform/mister/mister_top.sv` | MiSTer wrapper (stub) |
| `src/tools/test_vectors.py` | Python CRC-16 reference for test generation |

## RTL Conventions

- **Language**: SystemVerilog with Icarus Verilog compatibility
- **Simulator**: `iverilog -g2012` (avoid advanced SV features)
- **Timescale**: All modules use `` `timescale 1ns / 1ps ``

### Icarus Verilog Restrictions
- No `typedef struct packed` - use flattened `reg [N:0]` with localparam field indices
- No `typedef enum` - use `localparam [W:0] STATE = N'd0` style
- No `'{...}` array initialization - use tasks or loops
- No `break` in loops - use flag variables
- Avoid `automatic` in tasks

## Testing

Tests use self-checking testbenches with pass/fail counts:

```verilog
if (expected == actual) begin
    $display("PASS");
    pass_count = pass_count + 1;
end else begin
    $display("FAIL");
    fail_count = fail_count + 1;
end
```

## Memory Map (GB)

```
VRAM (8KB):
  0x0000-0x17FF: Tile Data (384 tiles, 16 bytes each)
  0x1800-0x1BFF: BG Map 1
  0x1C00-0x1FFF: BG Map 2
```

## Hash Entry Format

41-bit entries: `{valid[1], hash[16], char_code[8], trans_ptr[16]}`

## Bloom Filter

- 3 hash functions: h1=hash, h2=byteswap(hash), h3=hash^0x5A5A
- Positive when all 3 bits set
- Used for fast rejection of non-Japanese tiles

## Python Tools

Use `uv` for Python (never raw pip):
```bash
uv run python src/tools/test_vectors.py --output tests/vectors
```

## Git Workflow

- Tag milestones: `git tag vX.Y.Z && git push origin vX.Y.Z`
- Never commit `setenv.sh` or `.env` files
