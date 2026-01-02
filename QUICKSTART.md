# Quick Start Guide

## What This Project Does

Intercepts Japanese text in Game Boy games and translates it to English in real-time on the Analogue Pocket.

## Prerequisites

Install these once:

```bash
# Simulators for testing the hardware code
sudo apt install iverilog verilator

# Python package manager
curl -LsSf https://astral.sh/uv/install.sh | sh
```

## Running Tests

```bash
cd ~/projects/gba-translate

# Run ALL tests (should see "ALL TESTS PASSED" 4 times)
make test
```

That's it. If you see this at the end, everything works:

```
=========================================
All tests completed
=========================================
```

## What the Tests Check

| Command | What it tests |
|---------|---------------|
| `make test-hash` | Tile fingerprinting (CRC-16 hash) |
| `make test-snooper` | Catching VRAM writes |
| `make test-lookup` | Dictionary lookups |
| `make test-integration` | Everything connected together |

## If Something Breaks

```bash
# Clean and rebuild
make clean
make test
```

## Project Structure (Simple Version)

```
gba-translate/
├── src/rtl/core/     ← The actual hardware code (SystemVerilog)
├── src/rtl/tb/       ← Tests for the hardware code
├── src/tools/        ← Python helpers
├── Makefile          ← Run "make test" from here
└── build/            ← Compiled test binaries (auto-generated)
```

## Next Steps (Not Implemented Yet)

1. Synthesize for Analogue Pocket (needs Quartus)
2. Create tile dictionaries for specific games
3. Integrate with GB core
