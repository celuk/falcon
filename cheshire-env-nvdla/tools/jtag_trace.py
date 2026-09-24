# Copyright 2026
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Seyyid Hikmet Celik <seyyid4091@gmail.com>

import sys
import telnetlib
import re

#telnet localhost 4444
#proc record_trace {n f} { set fd [open $f w]; for {set i 0} {$i < $n} {incr i} { regexp {0x[0-9a-fA-F]+} [reg pc] p; set d [capture "riscv.cpu mdb $p 4"]; puts $fd [string trim $d]; step }; close $fd }
#record_trace 50 "trace.txt"

def run_trace(filename, max_steps):
    HOST = "localhost"
    PORT = 4444
    TIMEOUT = 10

    try:
        tn = telnetlib.Telnet(HOST, PORT, TIMEOUT)
        tn.read_until(b"> ")
    except Exception as e:
        print(f"Connection failed: {e}")
        return

    print(f"Tracing to '{filename}'...")

    try:
        with open(filename, 'w') as f:
            for i in range(max_steps):
                tn.write(b"reg pc\n")
                pc_out = tn.read_until(b"> ").decode('utf-8')
                
                match = re.search(r'(0x[0-9a-fA-F]+)', pc_out)
                if not match:
                    break
                
                pc_addr = match.group(1)

                cmd = f"riscv.cpu mdb {pc_addr} 4\n"
                tn.write(cmd.encode('ascii'))
                mem_out = tn.read_until(b"> ").decode('utf-8')

                for line in mem_out.splitlines():
                    if pc_addr in line and ":" in line:
                        f.write(line.strip() + "\n")
                        break
                
                tn.write(b"step\n")
                tn.read_until(b"> ")

                if i % 100 == 0:
                    sys.stdout.write(f"\rStep: {i}/{max_steps}")
                    sys.stdout.flush()

    except KeyboardInterrupt:
        print("\nStopped by user.")
    except Exception as e:
        print(f"\nError: {e}")
    finally:
        tn.close()
        print(f"\nTrace finished.")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 jtag_trace.py <filename> <count>")
        sys.exit(1)

    fname = sys.argv[1]
    try:
        count = int(sys.argv[2])
    except ValueError:
        print("Error: Count must be an integer.")
        sys.exit(1)

    run_trace(fname, count)
