// Copyright 2026
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Seyyid Hikmet Celik <seyyid4091@gmail.com>

`define COMMON_CELLS_ASSERTS_OFF 1
`define ASSERTS_OFF 1
`define TARGET_SYNTHESIS

//`define DRAM_SIM
//`define SIM
//`define GENESYS2
//`define ZC706

// for cheshire_pkg.sv, same for vcu118
`define VCU108

`define CPU_CLK 50_000_000
`define BAUD_RATE 115200
`define PROG_BAUD_RATE 921600
`define DDR_MHZ 50

`define SV_TESTPOINTS_OFF 1
`define DESIGNWARE_NOEXIST 1
`define SYNTHESIS 1
`define FPGA 1
`define VLIB_BYPASS_POWER_CG 1
`define NV_FPGA_FIFOGEN 1
`define FIFOGEN_MASTER_CLK_GATING_DISABLED 1
//`define NV_FPGA_SYSTEM 1
//`define NV_FPGA_UNIT 1

`define JTAG

`define TARGET_VCU108
