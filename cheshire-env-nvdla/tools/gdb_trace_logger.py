# Copyright 2026
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Seyyid Hikmet Celik <seyyid4091@gmail.com>

import gdb
import sys

class RiscvTraceFileCommand(gdb.Command):
    def __init__(self):
        super(RiscvTraceFileCommand, self).__init__("trace_logger", gdb.COMMAND_USER)

    def invoke(self, arg, from_tty):
        args = arg.split()
        if len(args) < 1:
            print("Error: Please provide an output file path.")
            print("Usage: trace_logger <file_path> [max_insts]")
            return

        file_path = args[0]
        max_insts = 100000

        if len(args) >= 2:
            try:
                max_insts = int(args[1])
            except ValueError:
                print("Error: max_instructions must be an integer.")
                return

        try:
            f = open(file_path, 'w')
            print(f"Tracing started. Outputting to '{file_path}'...")
            print(f"Limit: {max_insts} instructions. Press CTRL+C to stop.")
        except IOError as e:
            print(f"Error opening file: {e}")
            return

        gdb.execute("set pagination off", to_string=True)

        try:
            header = f"{'Time(ns)':<10} {'Cycle':<10} {'PC':<18} {'InstrHex':<10} {'Disassembly'}\n"
            f.write(header)

            period_ns = 20

            for i in range(max_insts):
                try:
                    cycle = int(gdb.parse_and_eval("$mcycle"))
                except:
                    cycle = i

                time_ns = cycle * period_ns

                pc_val = int(gdb.parse_and_eval("$pc"))
                pc_str = f"0x{pc_val:016x}"

                try:
                    instr_int = int(gdb.parse_and_eval(f"*(unsigned int*){pc_val}"))
                    instr_hex = f"{instr_int & 0xFFFFFFFF:08x}"
                except:
                    instr_hex = "????????"

                try:
                    disasm_raw = gdb.execute("x/i $pc", to_string=True).strip()
                    if ":" in disasm_raw:
                        disasm = disasm_raw.split(":", 1)[1].strip()
                    else:
                        disasm = disasm_raw
                except:
                    disasm = "<error>"

                line = f"{time_ns:<10} {cycle:<10} {pc_str:<18} {instr_hex:<10} {disasm}\n"
                f.write(line)

                gdb.execute("stepi", to_string=True)

        except KeyboardInterrupt:
            print("\nTracing stopped by user (CTRL+C).")
        except gdb.error as e:
            print(f"\nGDB Error occurred: {e}")
        finally:
            f.close()
            print(f"Trace finished. Data written to {file_path}")

RiscvTraceFileCommand()
