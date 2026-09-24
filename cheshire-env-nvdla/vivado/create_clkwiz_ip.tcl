# Copyright 2026
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Seyyid Hikmet Celik <seyyid4091@gmail.com>

set proj "clk_wiz_0"

create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name $proj

set_property -dict [list \
                    CONFIG.PRIM_SOURCE {No_buffer} \
                    CONFIG.PRIM_IN_FREQ {200.000} \
                    CONFIG.CLKOUT1_USED {true} \
                    CONFIG.CLKOUT2_USED {true} \
                    CONFIG.CLKOUT3_USED {true} \
                    CONFIG.CLKOUT4_USED {true} \
                    CONFIG.CLK_OUT1_PORT {clk_50} \
                    CONFIG.CLK_OUT2_PORT {clk_48} \
                    CONFIG.CLK_OUT3_PORT {clk_20} \
                    CONFIG.CLK_OUT4_PORT {clk_10} \
                    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {50.000} \
                    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {48.000} \
                    CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {20.000} \
                    CONFIG.CLKOUT4_REQUESTED_OUT_FREQ {10.000} \
                    CONFIG.CLKIN1_JITTER_PS {50.0} \
                    CONFIG.MMCM_CLKFBOUT_MULT_F {6.000} \
                    CONFIG.MMCM_CLKIN1_PERIOD {5.000} \
                    CONFIG.MMCM_CLKOUT1_DIVIDE {24} \
                    CONFIG.MMCM_CLKOUT2_DIVIDE {25} \
                    CONFIG.MMCM_CLKOUT3_DIVIDE {60} \
                    CONFIG.MMCM_CLKOUT4_DIVIDE {120} \
                    CONFIG.NUM_OUT_CLKS {4} \
                    CONFIG.CLKOUT1_JITTER {112.316} \
                    CONFIG.CLKOUT1_PHASE_ERROR {89.971} \
                    CONFIG.CLKOUT2_JITTER {129.198} \
                    CONFIG.CLKOUT2_PHASE_ERROR {89.971} \
                    CONFIG.CLKOUT3_JITTER {155.330} \
                    CONFIG.CLKOUT3_PHASE_ERROR {89.971} \
                    CONFIG.CLKOUT4_JITTER {178.053} \
                    CONFIG.CLKOUT4_PHASE_ERROR {89.971} \
                    ] [get_ips $proj]
