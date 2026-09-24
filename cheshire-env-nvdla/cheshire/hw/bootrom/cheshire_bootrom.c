// Copyright 2022 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Nicole Narr <narrn@student.ethz.ch>
// Christopher Reinwardt <creinwar@student.ethz.ch>
// Paul Scheffler <paulsc@iis.ee.ethz.ch>
// Seyyid Hikmet Celik <seyyid4091@gmail.com>

#include <stdint.h>
#include "util.h"
#include "params.h"
#include "regs/cheshire.h"
#include "spi_host_regs.h"
#include "dif/clint.h"
#include "hal/i2c_24fc1025.h"
#include "hal/spi_s25fs512s.h"
#include "hal/spi_sdcard.h"
#include "hal/uart_debug.h"
#include "gpt.h"

extern int boot_next_stage(void *);

int boot_passive(uint64_t core_freq) {
    // Initialize UART with debug settings
    uart_debug_init(&__base_uart, core_freq);
    // scratch[0] provides an entry point, scratch[1] a start signal
    volatile uint32_t *scratch = reg32(&__base_regs, CHESHIRE_SCRATCH_0_REG_OFFSET);
    // While we poll bit 2 of scratch[2], check for incoming UART debug requests
    while (!(scratch[2] & 2))
        if (uart_debug_check(&__base_uart)) return uart_debug_serve(&__base_uart);
    // No UART (or JTAG) requests came in, but scratch[2][2] was set --> run code at scratch[1:0]
    scratch[2] = 0;
    return boot_next_stage((void *)(uintptr_t)(((uint64_t)scratch[1] << 32) | scratch[0]));
}

struct fw_dynamic_info {
    unsigned long magic; // uint64_t
    unsigned long version;
    unsigned long next_addr;
    unsigned long next_mode;
    unsigned long options;
    unsigned long boot_hart;
};

#define DDR3_AXI_BASE_ADDR 0x80000000UL
#define OPENSBI_BASE_ADDR DDR3_AXI_BASE_ADDR

#define FW_DYNAMIC_INFO_MAGIC_VALUE 0x4942534f
#define FW_DYNAMIC_INFO_VERSION_2 0x2
#define FW_DYNAMIC_INFO_VERSION_MAX FW_DYNAMIC_INFO_VERSION_2
#define FW_DYNAMIC_INFO_NEXT_MODE_U 0x0
#define FW_DYNAMIC_INFO_NEXT_MODE_S 0x1
#define FW_DYNAMIC_INFO_NEXT_MODE_M 0x3
#define FW_DYNAMIC_NEXT_ADDRESS_OFFSET 0x00200000
#define FW_DYNAMIC_NEXT_ADDRESS (OPENSBI_BASE_ADDR + FW_DYNAMIC_NEXT_ADDRESS_OFFSET)

#define BOOT_HART_ID 0x0

#define DTB_ADDRESS_OFFSET 0x00140000
#define DTB_ADDRESS (OPENSBI_BASE_ADDR + DTB_ADDRESS_OFFSET) // fw_fdt_bin (compiled dts - dtb file) address

int boot_from_dram(uint64_t core_freq, uint64_t rtc_freq) {
    clint_spin_until((500 * rtc_freq) / (1000 * 1000) + 1);
    //// Initialize UART with debug settings
    //uart_debug_init(&__base_uart, core_freq);
    //// scratch[0] provides an entry point, scratch[1] a start signal
    //volatile uint32_t *scratch = reg32(&__base_regs, CHESHIRE_SCRATCH_0_REG_OFFSET);
    //// While we poll bit 2 of scratch[2], check for incoming UART debug requests
    //while (!(scratch[2] & 2))
    //    if (uart_debug_check(&__base_uart)) return uart_debug_serve(&__base_uart);
    //// No UART (or JTAG) requests came in, but scratch[2][2] was set --> run code at scratch[1:0]
    //scratch[2] = 0;

    //uart_debug_init(&__base_uart, core_freq);

    struct fw_dynamic_info dynamic_info;
    dynamic_info.magic = FW_DYNAMIC_INFO_MAGIC_VALUE;
    dynamic_info.version = FW_DYNAMIC_INFO_VERSION_MAX;
    dynamic_info.next_addr = FW_DYNAMIC_NEXT_ADDRESS;
    dynamic_info.next_mode = FW_DYNAMIC_INFO_NEXT_MODE_S;
    dynamic_info.options = 0x00000000;
    dynamic_info.boot_hart = BOOT_HART_ID;

    unsigned int hart_id;
	__asm__ volatile("csrr %0, mhartid" : "=r"(hart_id));

    __asm__ volatile (
        "mv a0, %[hart_id]\n"
        "mv a1, %[dtb_addr]\n"
        "mv a2, %[info_addr]\n"
        :
        : [hart_id]"r"(hart_id),
          [dtb_addr]"r"(DTB_ADDRESS),
          [info_addr]"r"(&dynamic_info)
        : "a0", "a1", "a2"
    );

    volatile uint32_t *scratch = reg32(&__base_regs, CHESHIRE_SCRATCH_0_REG_OFFSET);
    uint64_t next_addr = OPENSBI_BASE_ADDR;
    scratch[0] = (uint32_t)(next_addr & 0xFFFFFFFF);
    scratch[1] = (uint32_t)(next_addr >> 32);

    return boot_next_stage((void *)(uintptr_t)(((uint64_t)scratch[1] << 32) | scratch[0]));
}

int boot_spi_sdcard(uint64_t core_freq, uint64_t rtc_freq) {
    // Initialize device handle
    spi_sdcard_t device = {
        .spi_freq = MIN(24 * 1000 * 1000, core_freq / 2), // Up to half core freq or 24MHz (<25MHz)
        .csid = 0,
        .csid_dummy = SPI_HOST_PARAM_NUM_C_S - 1 // Last physical CS is designated dummy
    };
    CHECK_CALL(spi_sdcard_init(&device, core_freq))
    // Wait for device to be initialized (1ms, round up extra tick to be sure)
    clint_spin_until((1000 * rtc_freq) / (1000 * 1000) + 1);
    return gpt_boot_part_else_raw(spi_sdcard_read_checkcrc, &device, &__base_spm,
                                  __BOOT_SPM_MAX_LBAS, __BOOT_ZSL_TYPE_GUID, 0);
}

int boot_spi_s25fs512s(uint64_t core_freq, uint64_t rtc_freq) {
    // Initialize device handle
    spi_s25fs512s_t device = {
        .spi_freq = MIN(40 * 1000 * 1000, core_freq / 4), // Up to quarter core freq or 40MHz
        .csid = 1};
    CHECK_CALL(spi_s25fs512s_init(&device, core_freq))
    // Wait for device to be initialized (t_PU = 300us, round up extra tick to be sure)
    clint_spin_until((350 * rtc_freq) / (1000 * 1000) + 1);
    return gpt_boot_part_else_raw(spi_s25fs512s_single_read, &device, &__base_spm,
                                  __BOOT_SPM_MAX_LBAS, __BOOT_ZSL_TYPE_GUID, 0);
}

int boot_i2c_24fc1025(uint64_t core_freq) {
    // Initialize device handle
    dif_i2c_t i2c;
    CHECK_CALL(i2c_24fc1025_init(&i2c, core_freq))
    return gpt_boot_part_else_raw(i2c_24fc1025_read, &i2c, &__base_spm, __BOOT_SPM_MAX_LBAS,
                                  __BOOT_ZSL_TYPE_GUID, 0);
}

int main() {
    // Read boot mode and reference frequency
    uint32_t bootmode = *reg32(&__base_regs, CHESHIRE_BOOT_MODE_REG_OFFSET);
    uint32_t rtc_freq = *reg32(&__base_regs, CHESHIRE_RTC_FREQ_REG_OFFSET);
    // Compute the boot core frequency using the reference clock
    uint64_t core_freq = clint_get_core_freq(rtc_freq, 2500);
    // In case of reentry, store return in scratch0 as is convention
    switch (bootmode) {
    case 0:
        //return boot_passive(core_freq);
        return boot_from_dram(core_freq, rtc_freq);
    case 1:
        return boot_spi_sdcard(core_freq, rtc_freq);
    case 2:
        return boot_spi_s25fs512s(core_freq, rtc_freq);
    case 3:
        return boot_i2c_24fc1025(core_freq);
    default:
        return boot_passive(core_freq);
    }
}
