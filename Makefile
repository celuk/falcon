# Copyright 2022 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Nicole Narr <narrn@student.ethz.ch>
# Christopher Reinwardt <creinwar@student.ethz.ch>
# Paul Scheffler <paulsc@iis.ee.ethz.ch>

XILINX_VIVADO ?= /tools/Xilinx/Vivado/2022.2

CHS_ROOT := $(shell realpath .)
BENDER	 ?= bender -d $(CHS_ROOT)

all:

include cheshire.mk

# Locally, make Cheshire phonies available without `chs_` prefix
define chs_phony_fwd_rule
$(patsubst chs-%,%,$(1)): $(1)
endef

$(foreach phony,$(CHS_PHONY),$(eval $(call chs_phony_fwd_rule,$(phony))))

help:
	@echo "Possible phonies (may not all be implemented):"
	@$(foreach phony,$(sort $(CHS_PHONY)),echo '- $(patsubst chs-%,%,$(phony))';)

ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))

.PHONY: jtag
jtag:
	/media/shc/0EDEBC4906059163/tools/riscv-openocd/src/openocd -f verification/jtag/debug_soc.cfg

.PHONY: gdb
gdb:
	gdb-multiarch -ex "target remote :3333"

.PHONY: pico
pico:
	picocom -b 115200 /dev/ttyUSB$(ARGS) --imap lfcrlf

.PHONY: program
program:
	$(XILINX_VIVADO)/bin/vivado -mode batch -nolog -nojournal -source util/program_vcu108.tcl -tclargs $(ARGS)

.PHONY: program_linux
program_linux:
	$(MAKE) program ARGS="/home/shc/projects/cheshire-env-nvdla-g2/target/xilinx/build/vcu108.cheshire/cheshire.runs/impl_1/cheshire_top_xilinx.bit"
	python3 cheshire-env-nvdla/tools/uart_send_data_to_dram.py -f /home/shc/projects/cheshire-linux-nvdla/riscv-opensbi-port/platform/template/custom.dtb.hex -p /dev/ttyUSB$(ARGS) -sa 0x00140000 -b 115200 -pb 921600
	python3 cheshire-env-nvdla/tools/uart_send_data_to_dram.py -f /home/shc/projects/cheshire-linux-nvdla/riscv-linux-port/arch/riscv/boot/Image.hex -p /dev/ttyUSB$(ARGS) -sa 0x00200000 -b 115200 -pb 921600
	python3 cheshire-env-nvdla/tools/uart_send_data_to_dram.py -f /home/shc/projects/cheshire-linux-nvdla/riscv-opensbi-port/build/platform/template/firmware/fw_dynamic.hex -p /dev/ttyUSB$(ARGS) -sa 0x0 -b 115200 -pb 921600

.PHONY: reset
reset:
	python3 cheshire-env-nvdla/tools/uart_send_reset.py --port /dev/ttyUSB$(word 2, $(MAKECMDGOALS)) -b 921600;

.PHONY: program_linux_problematic_cable plpc
program_linux_problematic_cable:
	@sed -i 's/set_property PARAM\.FREQUENCY [0-9]\+/set_property PARAM.FREQUENCY 3000000/g' util/program_vcu108.tcl;
	-$(MAKE) program ARGS="/home/shc/projects/cheshire-env-nvdla-g2/target/xilinx/build/vcu108.cheshire/cheshire.runs/impl_1/cheshire_top_xilinx.bit";
	sed -i 's/set_property PARAM\.FREQUENCY [0-9]\+/set_property PARAM.FREQUENCY 5000000/g' util/program_vcu108.tcl;
	-$(MAKE) program ARGS="/home/shc/projects/cheshire-env-nvdla-g2/target/xilinx/build/vcu108.cheshire/cheshire.runs/impl_1/cheshire_top_xilinx.bit";
	python3 cheshire-env-nvdla/tools/uart_send_data_to_dram.py -f /home/shc/projects/cheshire-linux-nvdla/riscv-opensbi-port/platform/template/custom.dtb.hex -p /dev/ttyUSB$(ARGS) -sa 0x00140000 -b 115200 -pb 921600;
	python3 cheshire-env-nvdla/tools/uart_send_data_to_dram.py -f /home/shc/projects/cheshire-linux-nvdla/riscv-linux-port/arch/riscv/boot/Image.hex -p /dev/ttyUSB$(ARGS) -sa 0x00200000 -b 115200 -pb 921600;
	python3 cheshire-env-nvdla/tools/uart_send_data_to_dram.py -f /home/shc/projects/cheshire-linux-nvdla/riscv-opensbi-port/build/platform/template/firmware/fw_dynamic.hex -p /dev/ttyUSB$(ARGS) -sa 0x0 -b 115200 -pb 921600;

plpc: program_linux_problematic_cable

%:
	@:
