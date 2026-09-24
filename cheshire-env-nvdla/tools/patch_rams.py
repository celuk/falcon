# Copyright 2026
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Seyyid Hikmet Celik <seyyid4091@gmail.com>

import os
import re
import glob

def get_ram_params(filename):
    # filename format: RAMDP_128X11_GL_M2_E2.v or RAMPDP_64X64_GL_M1_D2.v
    basename = os.path.basename(filename)
    # Extract dimensions: e.g. 128X11
    # Look for patterns like _(\d+)X(\d+)_
    match = re.search(r'_(\d+)X(\d+)_', basename)
    if match:
        words = int(match.group(1))
        bits = int(match.group(2))
        return words, bits
    return None, None

def generate_synth_block(module_name, words, bits, ram_type):
    # ram_type: 'RAMDP' or 'RAMPDP'
    # RAMDP: True Dual Port
    # RAMPDP: Pseudo Dual Port (One Read, One Write)
    
    # We need to adapt the port names found in the module potentially, 
    # but standard NVDLA RAMs strictly follow naming:
    # CLK_R, CLK_W (or CLOCK, CLOCK_W)
    # WA, RA (or WADR, RADR)
    # WD, RD (or WDATA, RDATA)
    # RE, WE
    
    # Since we are inside the module, we can use the exact signal names if we know them.
    # However, NVDLA RAMs vary slightly. 
    # Some use CLK_R/CLK_W. Some use "CLOCK" (single clock?).
    
    # Best approach: Use the port names from the module definition if possible?
    # Or just use the known standard signal names for these files.
    # The user provided `RAMDP_128X11_GL_M2_E2.v` uses:
    # CLK_R, CLK_W, RE, WE, RA, WA, WD, RD
    
    # Let's inspect the module header inside the patching loop to detect clock names?
    # Or just generate a generic block that uses common names found in these files.
    # We can refine this.
    pass

def patch_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    words, bits = get_ram_params(filepath)
    if not words:
        print(f"Skipping {filepath}: Cannot determine params")
        return

    basename = os.path.basename(filepath)
    is_pdp = "RAMPDP" in basename
    is_dp = "RAMDP" in basename and not is_pdp

    # Define standard synthesis block templates
    # We must match the port names used in the file.
    
    # Helper to check for signal existence
    def has_signal(text, name):
        return re.search(r'\b' + name + r'\b', text)

    new_content = ""
    last_end = 0
    
    # Find all modules
    # Use ungreedy .*? for body
    module_pattern = re.compile(r"(module\s+(\w+)\s*\(.*?\)\s*;)(.*?)(endmodule)", re.DOTALL)
    
    matches = list(module_pattern.finditer(content))
    
    if not matches:
        # Maybe formatting issues?
        print(f"No modules found in {filepath}")
        return

    # We rebuild the file
    for m in matches:
        full_match = m.group(0)
        header = m.group(1)
        module_name = m.group(2)
        body = m.group(3)
        footer = m.group(4) # endmodule
        
        start_idx = m.start()
        end_idx = m.end()
        
        # Append content between modules (comments, etc)
        new_content += content[last_end:start_idx]
        
        # Determine port names from header + body (declarations)
        # Check clocks
        clk_w = "CLK_W" if has_signal(header, "CLK_W") else "CLOCK"
        clk_r = "CLK_R" if has_signal(header, "CLK_R") else "CLOCK"
        
        # Note: Some RAMPDP might use single CLK? 
        # RAMPDP_64X64_GL_M1_D2.v uses CLK (single) in some cases?
        # Let's verify commonly used names.
        # If CLK_W/CLK_R not found, look for CLOCK.
        
        # Check addresses
        ra = "RA" if has_signal(header + body, r"\bRA\b") else "RADR"
        wa = "WA" if has_signal(header + body, r"\bWA\b") else "WADR"
        
        # Check data
        wd = "WD" if has_signal(header + body, r"\bWD\b") else "WDATA"
        rd = "RD" if has_signal(header + body, r"\bRD\b") else "RDATA"
        
        # Check Enables
        we = "WE" if has_signal(header + body, r"\bWE\b") else "WRITE_EN"
        re_sig = "RE" if has_signal(header + body, r"\bRE\b") else "READ_EN"
        
        # For PDP, RE might be implicit or CS? 
        # RAMDP_... has RE.
        
        # Construct Synthesis Block
        # Indentation for readability
        synth_logic = ""
        synth_logic += f"\n`ifdef SYNTHESIS\n"
        synth_logic += f"    localparam bits = {bits};\n"
        synth_logic += f"    localparam words = {words};\n"
        synth_logic += f"    (* ram_style = \"block\" *) reg [{bits-1}:0] array [0:{words-1}];\n"
        synth_logic += f"    reg [{bits-1}:0] r_data;\n"
        synth_logic += f"\n"
        
        # Write Logic (Common)
        synth_logic += f"    always @(posedge {clk_w}) begin\n"
        synth_logic += f"        if ({we}) array[{wa}] <= {wd};\n"
        synth_logic += f"    end\n"
        synth_logic += f"\n"
        
        # Read Logic
        if is_dp: # True Dual Port (Has Read enable usually)
             synth_logic += f"    always @(posedge {clk_r}) begin\n"
             if has_signal(header + body, r"\b" + re_sig + r"\b"):
                 synth_logic += f"        if ({re_sig}) r_data <= array[{ra}];\n"
             else:
                 # Default to read always if no RE?
                 synth_logic += f"        r_data <= array[{ra}];\n"
             synth_logic += f"    end\n"
        else:
             # RAMPDP (Pseudo Dual Port) - usually read on CLK_R (or CLK)
             # One R port, One W port.
             synth_logic += f"    always @(posedge {clk_r}) begin\n"
             if has_signal(header + body, r"\b" + re_sig + r"\b"):
                 synth_logic += f"        if ({re_sig}) r_data <= array[{ra}];\n"
             else:
                 synth_logic += f"        r_data <= array[{ra}];\n"
             synth_logic += f"    end\n"

        synth_logic += f"    assign {rd} = r_data;\n"
        synth_logic += f"\n`else\n"
        
        # Determine insertion point (End of ports)
        # We search inside 'body' which starts after parenthesis+semicolon of module.
        # But 'header' captured `module ... ;` so 'body' starts immediately after first semicolon.
        # However, port declarations like `input ...;` are inside `body`.
        
        # Find the last input/output/inout declaration in body.
        last_port_match = None
        # Use DOTALL to handle multi-line declarations ending with ;
        for pm in re.finditer(r"^\s*(input|output|inout)\b.*?;", body, re.MULTILINE | re.DOTALL):
            last_port_match = pm

            
        if last_port_match:
            insert_pos = last_port_match.end()
            
            # Reconstruct module part
            # Header
            # Body[:insert_pos] -> includes declarations
            # Synth Block
            # Body[insert_pos:] -> Logic wrapped in else
            # Endif
            # Endmodule
            
            new_module = header + body[:insert_pos] + synth_logic + body[insert_pos:] + "\n`endif // SYNTHESIS\n" + footer
            new_content += new_module
        else:
            # Fallback if no explicit Declarations found (e.g. ANSI style header was used, so body has no inputs)
            # Insert at beginning of body
            new_module = header + synth_logic + body + "\n`endif // SYNTHESIS\n" + footer
            new_content += new_module

        last_end = end_idx

    new_content += content[last_end:]
    
    with open(filepath, 'w') as f:
        f.write(new_content)
    print(f"Patched {filepath}")

def main():
    files = glob.glob("**/*RAM*.v", recursive=True)
    # Filter to only get ones in nvdla/block-nvdla-sifive
    # files = [f for f in files if "block-nvdla-sifive" in f and "sim" not in f and "tb" not in f]
    files = [f for f in files if "check_verilog" not in f and "patch_rams" not in f] # Safety

    
    print(f"Found {len(files)} files to patch.")
    for f in files:
        try:
            patch_file(f)
        except Exception as e:
            print(f"Failed to patch {f}: {e}")

if __name__ == "__main__":
    main()
