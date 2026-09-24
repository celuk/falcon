restore /home/shc/projects/cheshire-linux-nvdla/riscv-opensbi-port/platform/template/custom.dtb binary 0x80140000
restore /home/shc/projects/cheshire-linux-nvdla/riscv-linux-port/arch/riscv/boot/Image binary 0x80200000
load /home/shc/projects/cheshire-linux-nvdla/riscv-opensbi-port/build/platform/template/firmware/fw_dynamic.elf
continue
