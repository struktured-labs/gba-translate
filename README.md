# GB/GBA Translation FPGA Core

Real-time Japanese text translation overlay for Game Boy and Game Boy Advance games, targeting the Analogue Pocket (openFPGA).

## Overview

This FPGA core intercepts VRAM writes to detect Japanese text tiles and provides translation via two modes:

1. **Replace Mode**: Substitutes Japanese tiles with English equivalents in-place
2. **Caption Mode**: Renders English translation as a subtitle overlay

## Project Status

🚧 **Early Development** - Core architecture and RTL modules implemented, simulation tests passing, not yet synthesized.

[![Tests](https://img.shields.io/badge/tests-29%20passing-brightgreen)]()
[![Version](https://img.shields.io/badge/version-v0.3.0-blue)]()

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     translation_overlay_top                      │
├─────────────────────────────────────────────────────────────────┤
│  vram_snooper ──▶ tile_hasher ──▶ hash_lookup_table             │
│       │                                   │                      │
│       ▼                                   ▼                      │
│  text_assembler ◀──────────────── translation_engine            │
│       │                                   │                      │
│       └───────────▶ display_mux ◀─────────┘                     │
│                    /            \                                │
│           replace_mode    caption_mode                          │
└─────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
gba-translate/
├── src/
│   ├── rtl/
│   │   ├── core/           # Main translation logic
│   │   ├── memory/         # Font ROM, dictionaries
│   │   └── gb_core/        # Modified GB core (future)
│   └── tools/              # Python utilities
├── data/
│   ├── fonts/              # ASCII bitmap fonts
│   └── games/              # Per-game dictionaries
└── docs/                   # Documentation
```

## Getting Started

### Prerequisites

- Intel Quartus Prime Lite (21.1+)
- Analogue openFPGA SDK
- Python 3.10+ with `uv`

### Setup

```bash
# Clone repository
git clone https://github.com/struktured-labs/gba-translate.git
cd gba-translate

# Install Python dependencies
uv sync

# Run tests (requires iverilog)
make test
```

## Testing

Requires [Icarus Verilog](http://iverilog.icarus.com/) and optionally [Verilator](https://verilator.org/) for linting.

```bash
# Install simulators (Ubuntu/Debian)
sudo apt install iverilog verilator

# Run all tests (29 tests)
make test

# Individual test suites
make test-hash        # Tile hash generator (8 tests)
make test-snooper     # VRAM snooper (4 tests)
make test-lookup      # Hash lookup table (12 tests)
make test-integration # End-to-end pipeline (5 tests)

# Lint check
make lint
```

### Test Coverage

| Module | Tests | Description |
|--------|-------|-------------|
| tile_hash_generator | 8 | CRC-16-CCITT computation |
| vram_snooper | 4 | VRAM write capture & streaming |
| hash_lookup_table | 12 | Bloom filter + hash table lookup |
| integration | 5 | End-to-end pipeline verification |

## Target Games

Starting with Game Boy (simpler architecture) before GBA:

- **Pokemon Green/Red (JP)** - First target, well-documented font system
- Future: Fire Emblem, Mother 3, etc.

## Technical Details

### Detection Pipeline

1. **VRAM Snooper**: Monitors writes to tile data region (0x8000-0x97FF)
2. **Tile Hasher**: Computes CRC-16 hash of each 8x8 tile (16 bytes)
3. **Bloom Filter**: Fast rejection of non-Japanese tiles (8KB, ~2% false positive)
4. **Hash Table**: Precise character lookup with 4-entry chaining

### Memory Budget

| Component | Size |
|-----------|------|
| Bloom filter | 8 KB |
| Font ROM | 2.3 KB |
| Caption buffer | 1.4 KB |
| **Total BRAM** | ~17 KB |

## License

MIT License - See LICENSE file

## Contributing

Contributions welcome! See CONTRIBUTING.md for guidelines.

## Acknowledgments

- [Spiritualized openFPGA-GB](https://github.com/spiritualized1997/openFPGA-GB) - Base GB core
- [GBATEK](https://problemkaputt.de/gbatek.htm) - Technical documentation
- [font8x8](https://github.com/dhepper/font8x8) - Base font reference
