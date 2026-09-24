# Copyright 2026
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Seyyid Hikmet Celik <seyyid4091@gmail.com>

import os
import re
import sys

def get_ram_geometry(filename):
    basename = os.path.basename(filename)
    match = re.search(r'_(\d+)X(\d+)_', basename)
    if match:
        words = int(match.group(1))
        bits = int(match.group(2))
        return words, bits
    return None, None

def patch_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
    
    # 1. Find RAM_BANK module
    pattern = re.compile(r"(module\s+(RAM_BANK_\w+)\s*\(([^;]*?)\)\s*;)", re.DOTALL)
    match = pattern.search(content)
    if not match:
        return False
    
    full_declaration = match.group(0)
    module_name = match.group(2)
    port_list_str = match.group(3)
    header_end = match.end()
    
    words, bits = get_ram_geometry(filepath)
    if not words:
        return False

    # 2. Find end of module
    endmodule_match = re.search(r"\bendmodule\b", content[header_end:])
    if not endmodule_match:
         print(f"Error: No endmodule found in {filepath}")
         return False
    
    endmodule_idx = header_end + endmodule_match.start()
    module_body = content[header_end:endmodule_idx]

    # Analyze ports
    ports_set = set(re.findall(r'\b\w+\b', port_list_str))

    # 3. Find Insertion Point: After the last valid module port input/output/inout definition
    decl_pattern = re.compile(r"\b(input|output|inout)\s+(?:\[[^;]*?\]\s*)?([^;]+);", re.DOTALL)
    
    last_decl_end = 0
    found_decl = False
    
    for m in decl_pattern.finditer(module_body):
        names_str = m.group(2)
        names = re.findall(r'\b\w+\b', names_str)
        
        is_port_decl = False
        for n in names:
            if n in ports_set:
                is_port_decl = True
                break
        
        if is_port_decl:
            last_decl_end = m.end()
            found_decl = True
        
    if not found_decl:
        insertion_rel = 0
    else:
        insertion_rel = last_decl_end
        
    insertion_point = header_end + insertion_rel
    
    # Check if already patched at insertion point
    chunk = content[insertion_point:insertion_point+200]
    if "ifdef SYNTHESIS" in chunk:
        return False
        
    # Heuristics for signal names
    ports = ports_set # alias
    
    clk_w = "CLK_W" if "CLK_W" in ports else "CLK"
    clk_r = "CLK_R" if "CLK_R" in ports else "CLK"
    if "CLK" in ports and "CLK_W" not in ports:
        clk_w = "CLK"
        clk_r = "CLK"
        
    wa = "WA" if "WA" in ports else "WADR"
    ra = "RA" if "RA" in ports else "RADR"
    wd = "WD" if "WD" in ports else "WDATA"
    rd = "RD" if "RD" in ports else "RDATA"
    we = "WE" if "WE" in ports else "WRITE_EN"
    re_sig = "RE" if "RE" in ports else "READ_EN"

    is_dp = "RAMDP" in module_name and "RAMPDP" not in module_name
    
    # Build Block
    lines = []
    lines.append("")
    lines.append("`ifdef SYNTHESIS")
    lines.append("    // Force BRAM inference for FPGA")
    lines.append(f"    localparam dbits = {bits};")
    lines.append(f"    localparam dwords = {words};")
    lines.append(f"    (* ram_style = \"block\" *) reg [dbits-1:0] mem [0:dwords-1];")
    lines.append(f"    reg [dbits-1:0] r_data;")
    lines.append("")
    lines.append(f"    always @(posedge {clk_w}) begin")
    lines.append(f"        if ({we}) mem[{wa}] <= {wd};")
    lines.append(f"    end")
    lines.append("")
    lines.append(f"    always @(posedge {clk_r}) begin")
    if is_dp:
        lines.append(f"        if ({re_sig}) r_data <= mem[{ra}];")
    else:
        if "RE" in ports or "READ_EN" in ports:
             lines.append(f"        if ({re_sig}) r_data <= mem[{ra}];")
        else:
             lines.append(f"        r_data <= mem[{ra}];")
    lines.append(f"    end")
    lines.append(f"    assign {rd} = r_data;")
    lines.append("`else")
    lines.append("")
    
    patch_block = "\n".join(lines)
    
    part1 = content[:insertion_point]
    part3 = content[insertion_point:endmodule_idx]
    part4 = "\n`endif // SYNTHESIS\n" + content[endmodule_idx:]
    
    new_content = part1 + patch_block + part3 + part4
    
    with open(filepath, 'w') as f:
        f.write(new_content)
    
    print(f"Patched {filepath}")
    return True

def main():
    root = "vsrc"
    if len(sys.argv) > 1:
        root = sys.argv[1]
        
    print(f"Scanning {root}...")
    count = 0
    for dirpath, _, filenames in os.walk(root):
        for fname in filenames:
            if fname.endswith(".v") and "RAM" in fname:
                if patch_file(os.path.join(dirpath, fname)):
                    count += 1
    print(f"Total patched: {count}")

if __name__ == "__main__":
    main()
