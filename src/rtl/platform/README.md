# Platform Abstraction Layer

The translation core is platform-agnostic. Platform-specific wrappers live here.

## Directory Structure

```
platform/
├── common/        # Shared utilities (empty for now)
├── analogue/      # Analogue Pocket openFPGA wrapper
│   └── pocket_top.sv
└── mister/        # MiSTer FPGA wrapper
    └── mister_top.sv
```

## Architecture

```
┌─────────────────────────────────────────┐
│         Platform Wrapper                │
│   (pocket_top.sv or mister_top.sv)      │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │    translation_overlay_top        │  │
│  │         (shared core)             │  │
│  │                                   │  │
│  │  vram_snooper → tile_hash_gen     │  │
│  │       ↓              ↓            │  │
│  │  hash_lookup_table → renderer     │  │
│  └───────────────────────────────────┘  │
│                                         │
│  Platform-specific:                     │
│  - Clock generation (PLL)               │
│  - Memory controllers                   │
│  - Configuration interface              │
│  - GB core integration                  │
└─────────────────────────────────────────┘
```

## Analogue Pocket (openFPGA)

**File:** `analogue/pocket_top.sv`

**Status:** Stub (not yet functional)

**Key interfaces:**
- APF bridge for configuration
- 74.25 MHz clocks from APF
- Cartridge slot signals
- PSRAM for dictionary storage

**TODO:**
1. PLL for GB system clock (4.19 MHz)
2. APF bridge command handler
3. PSRAM controller integration
4. GB core integration (spiritualized1997/openFPGA-GB)
5. Cartridge VRAM snoop hookup

## MiSTer

**File:** `mister/mister_top.sv`

**Status:** Stub (not yet functional)

**Key interfaces:**
- HPS for ARM communication (ioctl)
- SDRAM for dictionary storage
- OSD status bits for configuration
- Direct video output

**TODO:**
1. HPS/ioctl handler for dictionary download
2. SDRAM controller integration
3. OSD menu definition (.mra file)
4. GB core integration (MiSTer-devel/Gameboy_MiSTer)
5. VRAM signal routing from GB core

## Shared Core Interface

Both wrappers instantiate `translation_overlay_top` with these signals:

| Signal Group | Signals | Description |
|--------------|---------|-------------|
| Clocks | `clk`, `clk_vid`, `rst_n` | System and video clocks |
| VRAM Snoop | `vram_we/addr/wdata` | Intercept tile writes |
| Video In | `vid_rgb_in`, `vid_de/vs/hs_in`, `vid_x/y` | From GB PPU |
| Video Out | `vid_rgb_out`, `vid_de/vs/hs_out` | With overlay |
| Dictionary | `dict_load_*`, `bloom_load_*` | Runtime loading |
| Config | `cfg_enable/mode/caption_*` | User settings |

## Adding a New Platform

1. Create `platform/<name>/<name>_top.sv`
2. Instantiate `translation_overlay_top`
3. Implement platform-specific:
   - Clock generation
   - Memory interface
   - Configuration registers
   - GB core integration
4. Add build files (Quartus QSF, Vivado TCL, etc.)
