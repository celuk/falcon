# Copyright 2026
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Seyyid Hikmet Celik <seyyid4091@gmail.com>

import argparse
import sys
from collections import OrderedDict

BASE_ADDRESS = 0x80000000
KERNEL_OFFSET = 0x00400000
DTB_OFFSET = 0x01400000

# DDR3 model parameters for Genesys2 (x4Gb, x16, MT41J256m16)
BA_BITS  = 3
ROW_BITS = 15
COL_BITS = 10
BL_MAX   = 8
DQ_BITS  = 16   # per chip

# Derived
COLS_PER_ROW  = 1 << COL_BITS   # 1024
ROWS_PER_BANK = 1 << ROW_BITS   # 32768
NUM_BANKS     = 1 << BA_BITS     # 8

# For a 32-bit DDR3 bus (2 x x16 chips):
BUS_WIDTH_BYTES = 4   # 32 bits = 4 bytes
BURST_BYTES     = BL_MAX * BUS_WIDTH_BYTES  # 8 * 4 = 32 bytes per BL=8 burst


def read_vmem_files(input_files):
    """Read .vmem files into a flat byte-addressed dictionary."""
    memory = OrderedDict()
    for input_file, offset_type in input_files:
        current_address = None
        try:
            with open(input_file, 'r') as f_in:
                for line in f_in:
                    line = line.strip()
                    if not line:
                        continue
                    if line.startswith('@'):
                        try:
                            base_addr = int(line[1:], 16)
                            if offset_type == 'i':
                                current_address = base_addr - BASE_ADDRESS
                            elif offset_type == 'i2':
                                current_address = base_addr + KERNEL_OFFSET
                            elif offset_type == 'i3':
                                current_address = base_addr + DTB_OFFSET
                        except ValueError:
                            current_address = None
                    elif current_address is not None:
                        byte_values = line.split()
                        for byte_str in byte_values:
                            try:
                                memory[current_address] = int(byte_str, 16)
                                current_address += 1
                            except ValueError:
                                pass
        except FileNotFoundError:
            print(f"Error: Input file not found at {input_file}")
            sys.exit(1)
    return memory


def byte_addr_to_ddr3_addr(byte_addr):
    """Convert a byte address to DDR3 {bank, row, col} packed address.

    For a 32-bit bus (2 x x16), each DDR3 column = 4 bytes (2 per chip).
    DDR3 col = byte_addr / 4.
    """
    total_col = byte_addr // BUS_WIDTH_BYTES
    col  = total_col % COLS_PER_ROW
    row  = (total_col // COLS_PER_ROW) % ROWS_PER_BANK
    bank = (total_col // COLS_PER_ROW // ROWS_PER_BANK) % NUM_BANKS
    addr = (bank << (ROW_BITS + COL_BITS)) | (row << COL_BITS) | col
    return addr


def generate_genesys2_init(memory, output_base):
    """Generate split init files for Genesys2 32-bit DDR3 bus (2 x x16 chips).

    Each init entry covers one BL=8 burst (32 bytes, 8 x 32-bit words).
    chip0 gets lower 16 bits of each word, chip1 gets upper 16 bits.
    Address is DDR3 {bank, row, col} format.
    """
    if not memory:
        for suffix in ['_chip0.txt', '_chip1.txt']:
            open(output_base + suffix, 'w').close()
        return

    start_addr = min(memory.keys())
    end_addr = max(memory.keys())

    # Align start to 32-byte (burst) boundary
    aligned_start = start_addr & ~(BURST_BYTES - 1)

    chip0_lines = []
    chip1_lines = []

    for burst_byte_addr in range(aligned_start, end_addr + BURST_BYTES, BURST_BYTES):
        # Read 32 bytes (8 x 32-bit words) for this burst
        words_32 = []
        has_data = False
        for w in range(BL_MAX):
            word_byte_addr = burst_byte_addr + w * BUS_WIDTH_BYTES
            b0 = memory.get(word_byte_addr + 0, 0x00)
            b1 = memory.get(word_byte_addr + 1, 0x00)
            b2 = memory.get(word_byte_addr + 2, 0x00)
            b3 = memory.get(word_byte_addr + 3, 0x00)
            word32 = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0  # little-endian
            words_32.append(word32)
            for offset in range(BUS_WIDTH_BYTES):
                if (word_byte_addr + offset) in memory:
                    has_data = True

        if not has_data:
            continue

        # DDR3 address for this burst (starting column)
        ddr3_addr = byte_addr_to_ddr3_addr(burst_byte_addr)

        # chip0: lower 16 bits of each 32-bit word
        # Model data format: data[15:0]=beat0, data[31:16]=beat1, ..., data[127:112]=beat7
        chip0_val = 0
        for w in range(BL_MAX):
            chip0_val |= (words_32[w] & 0xFFFF) << (w * DQ_BITS)

        # chip1: upper 16 bits of each 32-bit word
        chip1_val = 0
        for w in range(BL_MAX):
            chip1_val |= ((words_32[w] >> 16) & 0xFFFF) << (w * DQ_BITS)

        chip0_lines.append(f"{ddr3_addr:08X} {chip0_val:032X}")
        chip1_lines.append(f"{ddr3_addr:08X} {chip1_val:032X}")

    with open(output_base + '_chip0.txt', 'w') as f:
        f.write('\n'.join(chip0_lines) + '\n')
    with open(output_base + '_chip1.txt', 'w') as f:
        f.write('\n'.join(chip1_lines) + '\n')

    print(f"Generated {len(chip0_lines)} entries per chip")
    print(f"  chip0: {output_base}_chip0.txt")
    print(f"  chip1: {output_base}_chip1.txt")


def generate_single_init(memory, output_file):
    """Generate single init file (legacy mode for non-Genesys2 / single-chip)."""
    if not memory:
        open(output_file, 'w').close()
        return

    with open(output_file, 'w') as f_out:
        start_addr = min(memory.keys())
        end_addr = max(memory.keys())

        aligned_start = start_addr & ~15

        for addr in range(aligned_start, end_addr + 16, 16):
            bytes_16 = []
            has_data = False
            for i in range(16):
                byte_addr = addr + i
                byte_val = memory.get(byte_addr, 0x00)
                bytes_16.append(byte_val)
                if byte_addr in memory:
                    has_data = True

            if has_data:
                bytes_16.reverse()
                hex_parts = [f"{byte:02X}" for byte in bytes_16]
                data_word = "".join(hex_parts)
                f_out.write(f"{addr:08X} {data_word}\n")


def main():
    parser = argparse.ArgumentParser(
        description="Convert Verilog .vmem files to DDR3 model mem_init files.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "-i", "--input",
        help="Path to the input .vmem file."
    )
    parser.add_argument(
        "-i2",
        help="Path to the vmlinux .vmem file."
    )
    parser.add_argument(
        "-i3",
        help="Path to the dtb .vmem file."
    )
    parser.add_argument(
        "-o", "--output",
        default="mem_init",
        help="Output path. For --genesys2: base name (generates _chip0.txt, _chip1.txt).\n"
             "For legacy mode: full filename (default: mem_init.txt)."
    )
    parser.add_argument(
        "--genesys2", action="store_true",
        help="Generate split init files for Genesys2 32-bit DDR3 bus (2 x x16 chips).\n"
             "Produces <output>_chip0.txt and <output>_chip1.txt with:\n"
             "  - Correct DDR3 {bank,row,col} addresses (not byte addresses)\n"
             "  - Per-chip 16-bit data slices"
    )
    args = parser.parse_args()

    input_files = []
    if args.input:
        input_files.append((args.input, 'i'))
    if args.i2:
        input_files.append((args.i2, 'i2'))
    if args.i3:
        input_files.append((args.i3, 'i3'))

    if not input_files:
        print("Error: No input files provided. Use -i, -i2, or -i3.")
        sys.exit(1)

    memory = read_vmem_files(input_files)

    if args.genesys2:
        generate_genesys2_init(memory, args.output)
    else:
        output_file = args.output if args.output.endswith('.txt') else args.output + '.txt'
        generate_single_init(memory, output_file)


if __name__ == "__main__":
    main()
