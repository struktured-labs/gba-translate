#!/usr/bin/env python3
"""
test_vectors.py

Generates test vectors for RTL simulation verification.
Ensures Python and SystemVerilog implementations produce identical results.

Usage:
    uv run python src/tools/test_vectors.py --output tests/vectors/
"""

import argparse
import struct
from pathlib import Path
from dataclasses import dataclass


def crc16_ccitt(data: bytes, init: int = 0xFFFF) -> int:
    """
    CRC-16-CCITT (polynomial 0x1021).
    Must match tile_hash_generator.sv exactly.
    """
    crc = init
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


@dataclass
class TileTestVector:
    """Test vector for tile hash verification"""
    name: str
    tile_data: bytes  # 16 bytes
    expected_hash: int

    def to_hex_string(self) -> str:
        """Tile data as hex string for Verilog $readmemh"""
        return ''.join(f'{b:02X}' for b in self.tile_data)


def generate_tile_test_vectors() -> list[TileTestVector]:
    """Generate various test vectors for tile hashing"""
    vectors = []

    # Test 1: All zeros
    data = bytes(16)
    vectors.append(TileTestVector(
        name="all_zeros",
        tile_data=data,
        expected_hash=crc16_ccitt(data)
    ))

    # Test 2: All ones (0xFF)
    data = bytes([0xFF] * 16)
    vectors.append(TileTestVector(
        name="all_ones",
        tile_data=data,
        expected_hash=crc16_ccitt(data)
    ))

    # Test 3: Sequential bytes 0-15
    data = bytes(range(16))
    vectors.append(TileTestVector(
        name="sequential",
        tile_data=data,
        expected_hash=crc16_ccitt(data)
    ))

    # Test 4: Alternating pattern (checkerboard)
    data = bytes([0xAA, 0x55] * 8)
    vectors.append(TileTestVector(
        name="alternating",
        tile_data=data,
        expected_hash=crc16_ccitt(data)
    ))

    # Test 5: Simulated Japanese character tile (filled square)
    # 2bpp format: each row is 2 bytes (low bits, high bits)
    data = bytes([
        0xFF, 0xFF,  # Row 0: all pixels color 3
        0xFF, 0xFF,  # Row 1
        0xFF, 0xFF,  # Row 2
        0xFF, 0xFF,  # Row 3
        0xFF, 0xFF,  # Row 4
        0xFF, 0xFF,  # Row 5
        0xFF, 0xFF,  # Row 6
        0xFF, 0xFF,  # Row 7
    ])
    vectors.append(TileTestVector(
        name="filled_square",
        tile_data=data,
        expected_hash=crc16_ccitt(data)
    ))

    # Test 6: Letter 'A' pattern (similar to font)
    data = bytes([
        0x18, 0x00,  # Row 0:    ##
        0x3C, 0x00,  # Row 1:   ####
        0x66, 0x00,  # Row 2:  ##  ##
        0x66, 0x00,  # Row 3:  ##  ##
        0x7E, 0x00,  # Row 4:  ######
        0x66, 0x00,  # Row 5:  ##  ##
        0x66, 0x00,  # Row 6:  ##  ##
        0x00, 0x00,  # Row 7: (empty)
    ])
    vectors.append(TileTestVector(
        name="letter_a",
        tile_data=data,
        expected_hash=crc16_ccitt(data)
    ))

    # Test 7: Random-ish data (deterministic)
    import hashlib
    seed = hashlib.md5(b"test_vector_7").digest()[:16]
    data = bytes(seed)
    vectors.append(TileTestVector(
        name="pseudo_random",
        tile_data=data,
        expected_hash=crc16_ccitt(data)
    ))

    # Test 8: Single bit set
    data = bytes([0x80] + [0x00] * 15)
    vectors.append(TileTestVector(
        name="single_bit",
        tile_data=data,
        expected_hash=crc16_ccitt(data)
    ))

    return vectors


def generate_vram_write_vectors() -> list[dict]:
    """Generate test vectors for VRAM snooper"""
    vectors = []

    # Simulate writing a complete tile byte-by-byte
    tile_data = bytes(range(16))
    base_addr = 0x0100  # Tile index 16 (0x100 / 16 = 16)

    for i, byte_val in enumerate(tile_data):
        vectors.append({
            'addr': base_addr + i,
            'data': byte_val,
            'we': 1,
            'description': f'Write byte {i} of tile'
        })

    return vectors


def write_tile_vectors_hex(vectors: list[TileTestVector], output_dir: Path):
    """Write tile data as hex files for Verilog $readmemh"""
    output_dir.mkdir(parents=True, exist_ok=True)

    # Tile data file (one tile per line, 32 hex chars = 16 bytes)
    with open(output_dir / "tile_data.hex", 'w') as f:
        f.write("// Tile test vectors - 16 bytes per line\n")
        for v in vectors:
            f.write(f"{v.to_hex_string()}  // {v.name}\n")

    # Expected hashes file
    with open(output_dir / "expected_hashes.hex", 'w') as f:
        f.write("// Expected CRC-16 hashes\n")
        for v in vectors:
            f.write(f"{v.expected_hash:04X}  // {v.name}\n")

    # Combined file for easy verification
    with open(output_dir / "tile_test_vectors.txt", 'w') as f:
        f.write("# Tile Hash Test Vectors\n")
        f.write("# Format: name, hex_data, expected_hash\n\n")
        for v in vectors:
            f.write(f"{v.name}:\n")
            f.write(f"  data: {v.to_hex_string()}\n")
            f.write(f"  hash: 0x{v.expected_hash:04X} ({v.expected_hash})\n\n")


def write_verilog_include(vectors: list[TileTestVector], output_dir: Path):
    """Write Verilog include file with test vectors - Icarus Verilog compatible"""
    output_dir.mkdir(parents=True, exist_ok=True)

    with open(output_dir / "test_vectors.svh", 'w') as f:
        f.write("// Auto-generated test vectors - DO NOT EDIT\n")
        f.write("// Generated by test_vectors.py\n")
        f.write("// Compatible with Icarus Verilog\n\n")

        f.write(f"localparam NUM_TEST_VECTORS = {len(vectors)};\n\n")

        # Tile data as individual parameters (iverilog compatible)
        f.write("// Tile data: 128 bits (16 bytes) per vector\n")
        f.write("reg [127:0] TILE_DATA [0:NUM_TEST_VECTORS-1];\n")
        f.write("reg [15:0] EXPECTED_HASH [0:NUM_TEST_VECTORS-1];\n\n")

        # Initial block to set values
        f.write("// Initialize test vectors\n")
        f.write("task init_test_vectors;\n")
        f.write("begin\n")
        for i, v in enumerate(vectors):
            hex_str = v.to_hex_string()
            f.write(f"    TILE_DATA[{i}] = 128'h{hex_str};  // {v.name}\n")
        f.write("\n")
        for i, v in enumerate(vectors):
            f.write(f"    EXPECTED_HASH[{i}] = 16'h{v.expected_hash:04X};  // {v.name}\n")
        f.write("end\n")
        f.write("endtask\n\n")

        # Test names as function (strings in arrays are tricky in iverilog)
        f.write("// Get test name by index\n")
        f.write("function [127:0] get_test_name;\n")
        f.write("    input integer idx;\n")
        f.write("    begin\n")
        f.write("        case (idx)\n")
        for i, v in enumerate(vectors):
            # Pad name to 16 chars for consistent width
            padded = v.name.ljust(16)[:16]
            f.write(f'            {i}: get_test_name = "{padded}";\n')
        f.write('            default: get_test_name = "unknown         ";\n')
        f.write("        endcase\n")
        f.write("    end\n")
        f.write("endfunction\n")


def main():
    parser = argparse.ArgumentParser(description="Generate RTL test vectors")
    parser.add_argument("--output", "-o", type=Path, default=Path("tests/vectors"),
                        help="Output directory")
    args = parser.parse_args()

    print("Generating tile hash test vectors...")
    tile_vectors = generate_tile_test_vectors()

    print(f"Generated {len(tile_vectors)} test vectors:")
    for v in tile_vectors:
        print(f"  {v.name}: hash=0x{v.expected_hash:04X}")

    print(f"\nWriting to {args.output}/")
    write_tile_vectors_hex(tile_vectors, args.output)
    write_verilog_include(tile_vectors, args.output)

    print("\nFiles generated:")
    print(f"  {args.output}/tile_data.hex")
    print(f"  {args.output}/expected_hashes.hex")
    print(f"  {args.output}/tile_test_vectors.txt")
    print(f"  {args.output}/test_vectors.svh")

    return 0


if __name__ == "__main__":
    exit(main())
