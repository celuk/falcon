# Copyright 2026
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Seyyid Hikmet Celik <seyyid4091@gmail.com>

set proj "mig_7series_0"
set top_path "C:/Users/2640084/Desktop/ubuntu/shared/projects/cheshire-env-nvdla"
set project_root "${top_path}/vivado/cheshire_genesys2"
set src_prj_path "${top_path}/vivado/xdc/genesys2.mig7s.prj"
set prj_path "${project_root}/cheshire_genesys2.srcs/sources_1/ip/${proj}/mig_a.prj"

create_ip -name mig_7series -vendor xilinx.com -library ip -module_name $proj

file copy $src_prj_path $prj_path

set_property -dict [list \
    CONFIG.XML_INPUT_FILE {mig_a.prj} \
    CONFIG.RESET_BOARD_INTERFACE {Custom} \
    CONFIG.MIG_DONT_TOUCH_PARAM {Custom} \
    CONFIG.BOARD_MIG_PARAM {Custom} \
] [get_ips $proj]
