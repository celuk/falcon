# Copyright 2026
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Seyyid Hikmet Celik <seyyid4091@gmail.com>

import re
import sys

def check_syntax(filepath):
    with open(filepath, 'r') as f:
        lines = f.readlines()

    ifdef_stack = []
    module_stack = []

    for i, line in enumerate(lines):
        line_num = i + 1
        stripped = line.strip()
        
        # Remove comments
        if "//" in stripped and not stripped.startswith("`"): # Simple comment handling
             stripped = stripped.split("//")[0]

        if "`ifdef" in stripped or "`ifndef" in stripped:
            ifdef_stack.append((line_num, stripped))
        elif "`endif" in stripped:
            if not ifdef_stack:
                print(f"Error: Unmatched `endif at line {line_num}")
                return
            ifdef_stack.pop()
        
        if re.search(r'\bmodule\b', stripped) and not re.search(r'\bendmodule\b', stripped):
             module_stack.append((line_num, stripped))
        elif re.search(r'\bendmodule\b', stripped):
             if not module_stack:
                 # This might happen if file has multiple modules and we don't track carefully, or nested?
                 # Verilog modules don't nest usually.
                 print(f"Error: Unmatched endmodule at line {line_num}")
             else:
                 module_stack.pop()

    if ifdef_stack:
        for l, s in ifdef_stack:
            print(f"Error: Unclosed {s} starting at line {l}")
    
    if module_stack:
        for l, s in module_stack:
             print(f"Error: Unclosed module starting at line {l}: {s}")
    
    if not ifdef_stack and not module_stack:
        print("Syntax check passed: ifdefs and modules are balanced.")

if __name__ == "__main__":
    check_syntax(sys.argv[1])
