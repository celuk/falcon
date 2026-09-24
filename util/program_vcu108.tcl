# Copyright 2026
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Seyyid Hikmet Celik <seyyid4091@gmail.com>

open_hw_manager
connect_hw_server

set_property PARAM.FREQUENCY 5000000 [get_hw_targets localhost:3121/xilinx_tcf/Digilent/210308A1221C]

open_hw_target {localhost:3121/xilinx_tcf/Digilent/210308A1221C}

if { $argc > 0 } {
    set bitstream_file [lindex $argv 0]
} else {
    puts "No bitstream file specified, using default."
    set bitstream_file "/home/shc/projects/cheshire-env-nvdla-g2/target/xilinx/build/vcu108.cheshire/cheshire.runs/impl_1/cheshire_top_xilinx.bit"
}

current_hw_device [get_hw_devices xcvu095_0]
refresh_hw_device -update_hw_probes false [lindex [get_hw_devices xcvu095_0] 0]
set_property PROBES.FILE {} [get_hw_devices xcvu095_0]
set_property FULL_PROBES.FILE {} [get_hw_devices xcvu095_0]
set_property PROGRAM.FILE $bitstream_file [get_hw_devices xcvu095_0]
program_hw_devices [get_hw_devices xcvu095_0]
refresh_hw_device [lindex [get_hw_devices xcvu095_0] 0]

close_hw_manager
