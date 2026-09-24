# Copyright 2026
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Seyyid Hikmet Celik <seyyid4091@gmail.com>

define trace_logger
    if $argc < 2
        printf "Usage: trace_logger <filename> <count>\n"
    else
        set pagination off
        set logging file $arg0
        set logging overwrite on
        set logging redirect on
        set logging on
        
        set style enabled off
        
        printf "Cycle      PC               Disassembly\n"
        
        set $i = 0
        set $max = $arg1
        
        while $i < $max
            printf "%-10d 0x%016x ", $i, $pc
            
            x/1i $pc
            
            stepi
            
            set $i = $i + 1
        end
        
        set logging off
        set logging redirect off
        set style enabled on
        printf "Trace finished. Written to %s\n", $arg0
    end
end
