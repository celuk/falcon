// Copyright 2026
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Seyyid Hikmet Celik <seyyid4091@gmail.com>

`timescale 1ns/1ps

`include "cheshire/typedef.svh"

`include "header.vh"

//`default_nettype none

module cheshire_soc_wrap import cheshire_pkg::*;
(
  `ifdef ZC706
  input  wire clk_p,
  input  wire clk_n,
  `ifdef ZC706_MIG
  input wire sys_clk_p,
  input wire sys_clk_n,
  `endif
  `elsif GENESYS2
  input  wire sys_clk_p,
  input  wire sys_clk_n,
  `else
  input wire clk_i,
  `endif
  input  logic rst_ni,

  input  wire program_rx_i,
  output wire prog_mode_led_o,
   
  output wire uart_tx_o

`ifndef DRAM_SIM
  // DDR3 Interface
  ,output logic ddr3_reset_n,
  output logic ddr3_cke,
  output logic ddr3_ck_p,
  output logic ddr3_ck_n,
  output logic ddr3_cs_n,
  output logic ddr3_ras_n,
  output logic ddr3_cas_n,
  output logic ddr3_we_n,
  `ifdef GENESYS2
  output logic [2:0] ddr3_ba,
  output logic [14:0] ddr3_addr,
  output logic ddr3_odt,
  inout  logic [3:0] ddr3_dm,
  inout  logic [3:0] ddr3_dqs_p,
  inout  logic [3:0] ddr3_dqs_n,
  inout  logic [31:0] ddr3_dq
  `elsif ZC706_MIG
  output logic [2:0] ddr3_ba,
  output logic [13:0] ddr3_addr,
  output logic ddr3_odt,
  inout  logic [7:0] ddr3_dm,
  inout  logic [7:0] ddr3_dqs_p,
  inout  logic [7:0] ddr3_dqs_n,
  inout  logic [63:0] ddr3_dq
  `else
  output logic [2:0] ddr3_ba,
  output logic [13:0] ddr3_addr,
  output logic ddr3_odt,
  inout  logic [1:0] ddr3_dm,
  inout  logic [1:0] ddr3_dqs_p,
  inout  logic [1:0] ddr3_dqs_n,
  inout  logic [15:0] ddr3_dq
  `endif
`endif

  `ifdef JTAG
  , input wire jtag_tck_i,
  input wire jtag_tms_i,
  input wire jtag_tdi_i,
  output wire jtag_tdo_o
  `ifdef GENESYS2
  , input wire jtag_trst_ni
  `endif
  `endif
);

`ifdef ZC706
  `ifndef ZC706_MIG
    wire sys_clk_p;
    wire sys_clk_n;
  `endif
`endif

  logic [1:0] boot_mode_i = 2'b00;
  logic test_mode = 0;
  // JTAG
  logic jtag_tck = jtag_tck_i;
  logic jtag_trst_n;
  `ifdef GENESYS2
  assign jtag_trst_n = jtag_trst_ni;
  `else
  assign jtag_trst_n = 1'b1;
  `endif
  logic jtag_tms = jtag_tms_i;
  logic jtag_tdi = jtag_tdi_i;
  logic jtag_tdo;
  assign jtag_tdo_o = jtag_tdo;
  // I2C
  logic i2c_sda;
  logic i2c_scl;
  // SPI Host
  logic                  spih_sck;
  logic [SpihNumCs-1:0]  spih_csb;
  logic [3:0]            spih_sd;
  // Serial Link
  logic [SlinkNumChan-1:0]                    slink_rcv_clk_i;
  logic [SlinkNumChan-1:0]                    slink_rcv_clk_o;
  logic [SlinkNumChan-1:0][SlinkNumLanes-1:0]  slink_i;
  logic [SlinkNumChan-1:0][SlinkNumLanes-1:0]  slink_o;

  logic system_reset_o;
  logic uart_dram_write_we;
  logic [31:0] uart_dram_write_addr;
  logic [31:0] uart_dram_write_data;
  logic uart_dram_write_rst;
  logic uart_dram_mode;

  `ifdef BASYS3
     wire clkwiz_o;
     wire clkwiz_locked;
     clk_wiz_0 dutclk (
        .clk_out1(clkwiz_o),
        .clk_in1(clk_i),
        .reset(~rst_ni),
        .locked(clkwiz_locked)
     );
     wire rst_n = rst_ni & system_reset_o & clkwiz_locked;
  `elsif ZC706
     wire pll_locked;
     wire clk100;
     wire clk_ddr;
     wire clk_ref;
     wire clk_ddr_dqs;
     wire clk_i;

     //wire sys_clk;
     //IBUFDS #(
     //  .IBUF_LOW_PWR ("FALSE")
     //) i_bufds_sys_clk (
     //  .I  ( sys_clk_p ),
     //  .IB ( sys_clk_n ),
     //  .O  ( sys_clk   )
     //);

     clk_wiz_0 u_pll
     //clk_wiz_1 u_pll
     (
        .clk_in1_p(clk_p),
        .clk_in1_n(clk_n)
        //.clk_in1(sys_clk)

        ,.reset(0)

        // first values for 100mhz, second values for 50mhz
        ,.clk_out1(clk100)      // 100, 50
        ,.clk_out2(clk_ddr)     // 400, 200
        ,.clk_out3(clk_ref)     // 200, 200
        ,.clk_out4(clk_ddr_dqs) // 400, 200 (phase 90)
        ,.clk_out5(clk_i)       // 100, 50
        ,.locked()
     );

     wire clkwiz_o = clk_i;
     wire rst_n = rst_ni & system_reset_o & !uart_dram_mode; // & !uart_dram_mode
     wire dram_ref_clk = clk_ref; //sys_clk;
  `elsif GENESYS2
     wire pll_locked;
     wire clk100;
     wire clk_ddr;
     wire clk_ref;
     wire clk_ddr_dqs;
     wire clk_i;
     
     wire sys_clk;
     IBUFDS #(
       .IBUF_LOW_PWR ("FALSE")
     ) i_bufds_sys_clk (
       .I  ( sys_clk_p ),
       .IB ( sys_clk_n ),
       .O  ( sys_clk   )
     );

     clk_wiz_0 u_pll (
        .clk_in1(sys_clk),
        //.clk_in1_p(sys_clk_p),
        //.clk_in1_n(sys_clk_n),
        .reset(~rst_ni),
        .clk_out1(clk100),
        .clk_out2(clk_ddr),
        .clk_out3(clk_ref),
        .clk_out4(clk_ddr_dqs),
        .clk_out5(clk_i),
        .locked(pll_locked)
     );

     wire clkwiz_o = clk_i;
     wire rst_n = rst_ni & system_reset_o & !uart_dram_mode & pll_locked;

     // For GENESYS2, MIG needs the raw 200 MHz IBUFDS output (sys_clk),
     // NOT a PLL-derived clock. The MIG has its own internal MMCM;
     // cascading PLLs causes jitter issues and calibration failures.
     wire dram_ref_clk = sys_clk;
  `else
     wire clkwiz_o = clk_i;
     wire rst_n = rst_ni & system_reset_o;
  `endif

  uart_programmer up_dram (
     .clk_i(clkwiz_o),
     .rst_ni(rst_ni `ifdef BASYS3 & clkwiz_locked `endif) // pll_locked
     
     ,.program_rx_i(program_rx_i)
     ,.system_reset_o(system_reset_o)
     ,.prog_mode_led_o(prog_mode_led_o)

     ,.dram_write_we_o(uart_dram_write_we)
     ,.dram_write_addr_o(uart_dram_write_addr)
     ,.dram_write_data_o(uart_dram_write_data)
     ,.dram_write_rst_o(uart_dram_write_rst)
     ,.dram_mode_o(uart_dram_mode)
  );
  
  logic rtc;
  `ifdef SIM
  clk_rst_gen #(
    .ClkPeriod    (100000ns), //( 30518000ns ),
    .RstClkCycles ( 5 )
  ) i_clk_rst_rtc (
    .clk_o  ( rtc ),
    .rst_no ( )
  );
  `else
  //assign rtc = 1'b0;
  /////////////////////////
  // "RTC" Clock Divider //
  /////////////////////////
  logic rtc_clk_d, rtc_clk_q;
  logic [15:0] counter_d, counter_q;

  assign rtc = rtc_clk_q;

  // Divide soc_clk (50 MHz) by 50 => 1 MHz RTC Clock
  always_comb begin
    counter_d = counter_q + 1;
    rtc_clk_d = rtc_clk_q;

    if(counter_q == 24) begin
      counter_d = '0;
      rtc_clk_d = ~rtc_clk_q;
    end
  end

  always_ff @(posedge clkwiz_o, negedge rst_n) begin
    if(~rst_n) begin
      counter_q <= '0;
      rtc_clk_q <= 0;
    end else begin
      counter_q <= counter_d;
      rtc_clk_q <= rtc_clk_d;
    end
  end
  `endif

  localparam cheshire_cfg_t WrapCfg = DefaultCfg;
  `CHESHIRE_TYPEDEF_ALL(, WrapCfg)

  axi_llc_req_t axi_llc_mst_req;
  axi_llc_rsp_t axi_llc_mst_rsp;

  logic i2c_sda_o;
  logic i2c_sda_i;
  logic i2c_sda_en;
  logic i2c_scl_o;
  logic i2c_scl_i;
  logic i2c_scl_en;

  logic                 spih_sck_o;
  logic                 spih_sck_en;
  logic [SpihNumCs-1:0] spih_csb_o;
  logic [SpihNumCs-1:0] spih_csb_en;
  logic [3:0]           spih_sd_o;
  logic [3:0]           spih_sd_i;
  logic [3:0]           spih_sd_en;

  cheshire_soc #(
    .Cfg                ( WrapCfg ),
    .ExtHartinfo        ( '0 ),
    .axi_ext_llc_req_t  ( axi_llc_req_t ),
    .axi_ext_llc_rsp_t  ( axi_llc_rsp_t ),
    .axi_ext_mst_req_t  ( axi_mst_req_t ),
    .axi_ext_mst_rsp_t  ( axi_mst_rsp_t ),
    .axi_ext_slv_req_t  ( axi_slv_req_t ),
    .axi_ext_slv_rsp_t  ( axi_slv_rsp_t ),
    .reg_ext_req_t      ( reg_req_t ),
    .reg_ext_rsp_t      ( reg_rsp_t )
  ) csoc (
    .clk_i              ( clkwiz_o       ),
    .rst_ni             ( rst_n     ),
    .test_mode_i        ( test_mode ),
    .boot_mode_i        ( boot_mode_i ),
    .rtc_i              ( rtc       ),
    .axi_llc_mst_req_o  ( axi_llc_mst_req ),
    .axi_llc_mst_rsp_i  ( axi_llc_mst_rsp ),
    .axi_ext_mst_req_i  ( '0 ),
    .axi_ext_mst_rsp_o  ( ),
    .axi_ext_slv_req_o  ( ),
    .axi_ext_slv_rsp_i  ( '0 ),
    .reg_ext_slv_req_o  (  ),
    .reg_ext_slv_rsp_i  ( '0 ),
    .intr_ext_i         ( '0 ),
    .intr_ext_o         ( ),
    .xeip_ext_o         ( ),
    .mtip_ext_o         ( ),
    .msip_ext_o         ( ),
    .dbg_active_o       ( ),
    .dbg_ext_req_o      ( ),
    .dbg_ext_unavail_i  ( '0 ),
    .jtag_tck_i         ( jtag_tck    ),
    .jtag_trst_ni       ( jtag_trst_n ),
    .jtag_tms_i         ( jtag_tms    ),
    .jtag_tdi_i         ( jtag_tdi    ),
    .jtag_tdo_o         ( jtag_tdo    ),
    .jtag_tdo_oe_o      ( ),
    .uart_tx_o          ( uart_tx_o ),
    .uart_rx_i          ( program_rx_i ),
    .uart_rts_no        ( ),
    .uart_dtr_no        ( ),
    .uart_cts_ni        ( 1'b0 ),
    .uart_dsr_ni        ( 1'b0 ),
    .uart_dcd_ni        ( 1'b0 ),
    .uart_rin_ni        ( 1'b0 ),
    .i2c_sda_o          ( i2c_sda_o  ),
    .i2c_sda_i          ( i2c_sda_i  ),
    .i2c_sda_en_o       ( i2c_sda_en ),
    .i2c_scl_o          ( i2c_scl_o  ),
    .i2c_scl_i          ( i2c_scl_i  ),
    .i2c_scl_en_o       ( i2c_scl_en ),
    .spih_sck_o         ( spih_sck_o  ),
    .spih_sck_en_o      ( spih_sck_en ),
    .spih_csb_o         ( spih_csb_o  ),
    .spih_csb_en_o      ( spih_csb_en ),
    .spih_sd_o          ( spih_sd_o   ),
    .spih_sd_en_o       ( spih_sd_en  ),
    .spih_sd_i          ( spih_sd_i   ),
    .gpio_i             ( '0 ),
    .gpio_o             ( ),
    .gpio_en_o          ( ),
    .slink_rcv_clk_i    ( slink_rcv_clk_i ),
    .slink_rcv_clk_o    ( slink_rcv_clk_o ),
    .slink_i            ( slink_i ),
    .slink_o            ( slink_o ),
    .vga_hsync_o        ( ),
    .vga_vsync_o        ( ),
    .vga_red_o          ( ),
    .vga_green_o        ( ),
    .vga_blue_o         ( ),
    .usb_clk_i          ( 1'b0 ),
    .usb_rst_ni         ( 1'b1 ),
    .usb_dm_i           ( '0 ),
    .usb_dm_o           ( ),
    .usb_dm_oe_o        ( ),
    .usb_dp_i           ( '0 ),
    .usb_dp_o           ( ),
    .usb_dp_oe_o        ( )
  );

  assign i2c_sda = i2c_sda_en ? i2c_sda_o : 1'bz;
  assign i2c_sda_i = i2c_sda;
  assign i2c_scl = i2c_scl_en ? i2c_scl_o : 1'bz;
  assign i2c_scl_i = i2c_scl;

  assign spih_sck = spih_sck_en ? spih_sck_o : 1'bz;
  assign spih_csb = spih_csb_en;
  assign spih_sd  = spih_sd_en;
  assign spih_sd_i = spih_sd;

  `ifdef DRAM_SIM
    `ifdef GENESYS2
    wire ddr3_reset_n;
    wire [0:0] ddr3_cke;
    wire ddr3_ck_p;
    wire ddr3_ck_n;
    wire [0:0] ddr3_cs_n;
    wire ddr3_ras_n;
    wire ddr3_cas_n;
    wire ddr3_we_n;
    wire [2:0] ddr3_ba;
    wire [14:0] ddr3_addr;
    wire [0:0] ddr3_odt;
    wire [3:0] ddr3_dm;
    wire [3:0] ddr3_dqs_p;
    wire [3:0] ddr3_dqs_n;
    wire [31:0] ddr3_dq;

    // Two x16 DDR3 chips to form 32-bit data bus (matching MIG DQ_WIDTH=32, MEMORY_WIDTH=16)
    // Chip 0: DQ[15:0], DQS[1:0], DM[1:0] — carries lower 16 bits of each 32-bit word
    ddr3_model #(
      //.MEM_INIT_FILE("../../../cheshire/sw/tests/helloworld.mem_init_chip0.txt")
    .MEM_INIT_FILE("")
    ) ddr3_chip0 (
      .rst_n  (ddr3_reset_n),
      .ck     (ddr3_ck_p),
      .ck_n   (ddr3_ck_n),
      .cke    (ddr3_cke),
      .cs_n   (ddr3_cs_n),
      .ras_n  (ddr3_ras_n),
      .cas_n  (ddr3_cas_n),
      .we_n   (ddr3_we_n),
      .dm_tdqs(ddr3_dm[1:0]),
      .ba     (ddr3_ba),
      .addr   ({1'b0, ddr3_addr}),
      .dq     (ddr3_dq[15:0]),
      .dqs    (ddr3_dqs_p[1:0]),
      .dqs_n  (ddr3_dqs_n[1:0]),
      .tdqs_n (),
      .odt    (ddr3_odt)
    );

    // Chip 1: DQ[31:16], DQS[3:2], DM[3:2] — carries upper 16 bits of each 32-bit word
    ddr3_model #(
      //.MEM_INIT_FILE("../../../cheshire/sw/tests/helloworld.mem_init_chip1.txt")
    .MEM_INIT_FILE("")
    ) ddr3_chip1 (
      .rst_n  (ddr3_reset_n),
      .ck     (ddr3_ck_p),
      .ck_n   (ddr3_ck_n),
      .cke    (ddr3_cke),
      .cs_n   (ddr3_cs_n),
      .ras_n  (ddr3_ras_n),
      .cas_n  (ddr3_cas_n),
      .we_n   (ddr3_we_n),
      .dm_tdqs(ddr3_dm[3:2]),
      .ba     (ddr3_ba),
      .addr   ({1'b0, ddr3_addr}),
      .dq     (ddr3_dq[31:16]),
      .dqs    (ddr3_dqs_p[3:2]),
      .dqs_n  (ddr3_dqs_n[3:2]),
      .tdqs_n (),
      .odt    (ddr3_odt)
    );
    `elsif ZC706_MIG
    wire ddr3_reset_n;
    wire ddr3_cke;
    wire ddr3_ck_p;
    wire ddr3_ck_n;
    wire ddr3_cs_n;
    wire ddr3_ras_n;
    wire ddr3_cas_n;
    wire ddr3_we_n;
    wire [2:0] ddr3_ba;
    wire [13:0] ddr3_addr;
    wire ddr3_odt;
    wire [7:0] ddr3_dm;
    wire [7:0] ddr3_dqs_p;
    wire [7:0] ddr3_dqs_n;
    wire [63:0] ddr3_dq;

    ddr3_model ddr3_dut0 (
      .rst_n  (ddr3_reset_n),
      .ck     (ddr3_ck_p),
      .ck_n   (ddr3_ck_n),
      .cke    (ddr3_cke),
      .cs_n   (ddr3_cs_n),
      .ras_n  (ddr3_ras_n),
      .cas_n  (ddr3_cas_n),
      .we_n   (ddr3_we_n),
      .dm_tdqs(ddr3_dm[1:0]),
      .ba     (ddr3_ba),
      .addr   (ddr3_addr),
      .dq     (ddr3_dq[15:0]),
      .dqs    (ddr3_dqs_p[1:0]),
      .dqs_n  (ddr3_dqs_n[1:0]),
      .tdqs_n (),
      .odt    (ddr3_odt)
    );

    ddr3_model ddr3_dut1 (
      .rst_n  (ddr3_reset_n),
      .ck     (ddr3_ck_p),
      .ck_n   (ddr3_ck_n),
      .cke    (ddr3_cke),
      .cs_n   (ddr3_cs_n),
      .ras_n  (ddr3_ras_n),
      .cas_n  (ddr3_cas_n),
      .we_n   (ddr3_we_n),
      .dm_tdqs(ddr3_dm[3:2]),
      .ba     (ddr3_ba),
      .addr   (ddr3_addr),
      .dq     (ddr3_dq[31:16]),
      .dqs    (ddr3_dqs_p[3:2]),
      .dqs_n  (ddr3_dqs_n[3:2]),
      .tdqs_n (),
      .odt    (ddr3_odt)
    );

    ddr3_model ddr3_dut2 (
      .rst_n  (ddr3_reset_n),
      .ck     (ddr3_ck_p),
      .ck_n   (ddr3_ck_n),
      .cke    (ddr3_cke),
      .cs_n   (ddr3_cs_n),
      .ras_n  (ddr3_ras_n),
      .cas_n  (ddr3_cas_n),
      .we_n   (ddr3_we_n),
      .dm_tdqs(ddr3_dm[5:4]),
      .ba     (ddr3_ba),
      .addr   (ddr3_addr),
      .dq     (ddr3_dq[47:32]),
      .dqs    (ddr3_dqs_p[5:4]),
      .dqs_n  (ddr3_dqs_n[5:4]),
      .tdqs_n (),
      .odt    (ddr3_odt)
    );

    ddr3_model ddr3_dut3 (
      .rst_n  (ddr3_reset_n),
      .ck     (ddr3_ck_p),
      .ck_n   (ddr3_ck_n),
      .cke    (ddr3_cke),
      .cs_n   (ddr3_cs_n),
      .ras_n  (ddr3_ras_n),
      .cas_n  (ddr3_cas_n),
      .we_n   (ddr3_we_n),
      .dm_tdqs(ddr3_dm[7:6]),
      .ba     (ddr3_ba),
      .addr   (ddr3_addr),
      .dq     (ddr3_dq[63:48]),
      .dqs    (ddr3_dqs_p[7:6]),
      .dqs_n  (ddr3_dqs_n[7:6]),
      .tdqs_n (),
      .odt    (ddr3_odt)
    );
    `else
    wire ddr3_reset_n;
    wire ddr3_cke;
    wire ddr3_ck_p;
    wire ddr3_ck_n;
    wire ddr3_cs_n;
    wire ddr3_ras_n;
    wire ddr3_cas_n;
    wire ddr3_we_n;
    wire [2:0] ddr3_ba;
    wire [13:0] ddr3_addr;
    wire ddr3_odt;
    wire [1:0] ddr3_dm;
    wire [1:0] ddr3_dqs_p;
    wire [1:0] ddr3_dqs_n;
    wire [15:0] ddr3_dq;

    ddr3 ddr3_dut (
      .rst_n  (ddr3_reset_n),
      .ck     (ddr3_ck_p),
      .ck_n   (ddr3_ck_n),
      .cke    (ddr3_cke),
      .cs_n   (ddr3_cs_n),
      .ras_n  (ddr3_ras_n),
      .cas_n  (ddr3_cas_n),
      .we_n   (ddr3_we_n),
      .dm_tdqs(ddr3_dm),
      .ba     (ddr3_ba),
      .addr   (ddr3_addr),
      .dq     (ddr3_dq),
      .dqs    (ddr3_dqs_p),
      .dqs_n  (ddr3_dqs_n),
      .tdqs_n (),
      .odt    (ddr3_odt)
    );
    `endif
  `endif

  dram_wrapper #(
    .axi_soc_aw_chan_t ( axi_llc_aw_chan_t ),
    .axi_soc_w_chan_t  ( axi_llc_w_chan_t  ),
    .axi_soc_b_chan_t  ( axi_llc_b_chan_t  ),
    .axi_soc_ar_chan_t ( axi_llc_ar_chan_t ),
    .axi_soc_r_chan_t  ( axi_llc_r_chan_t  ),
    .axi_soc_req_t     ( axi_llc_req_t     ),
    .axi_soc_resp_t    ( axi_llc_rsp_t     )
  ) dram_controller (
    .soc_resetn_i ( (rst_ni & system_reset_o) || uart_dram_mode ),
    .soc_clk_i    ( clkwiz_o ),

    .clk100       ( clk100 ),
    .clk_ddr      ( clk_ddr ),
    `ifdef GENESYS2
    .clk_ref      ( dram_ref_clk ),  // Raw 200 MHz from IBUFDS for MIG
    `elsif ZC706_MIG
    .clk_ref      ( dram_ref_clk ),
    `else
    .clk_ref      ( clk_ref ),
    `endif
    .clk_ddr_dqs  ( clk_ddr_dqs ),
    `ifdef ZC706_MIG
    .sys_clk_p    ( sys_clk_p ),
    .sys_clk_n    ( sys_clk_n ),
    `elsif GENESYS2
    .sys_clk_p    ( 1'b0 ),
    .sys_clk_n    ( 1'b0 ),
    `else
    .sys_clk_p    ( 1'b0 ),
    .sys_clk_n    ( 1'b0 ),
    `endif

    .uart_dram_write_we_i   ( uart_dram_write_we ),
    .uart_dram_write_addr_i ( uart_dram_write_addr ),
    .uart_dram_write_data_i ( uart_dram_write_data ),
    .uart_dram_write_rst_i  ( 0 ),

    // PHY interfaces
    .ddr3_ck_p    ( ddr3_ck_p ),
    .ddr3_ck_n    ( ddr3_ck_n ),
    .ddr3_dq      ( ddr3_dq ),
    .ddr3_dqs_n   ( ddr3_dqs_n ),
    .ddr3_dqs_p   ( ddr3_dqs_p ),
    .ddr3_addr    ( ddr3_addr ),
    .ddr3_ba      ( ddr3_ba ),
    .ddr3_ras_n   ( ddr3_ras_n ),
    .ddr3_cas_n   ( ddr3_cas_n ),
    .ddr3_we_n    ( ddr3_we_n ),
    .ddr3_reset_n ( ddr3_reset_n ),
    .ddr3_cke     ( ddr3_cke ),
    .ddr3_cs_n    ( ddr3_cs_n ),
    .ddr3_dm      ( ddr3_dm ),
    .ddr3_odt     ( ddr3_odt ),

    // DRAM AXI interface
    .soc_req_i    ( axi_llc_mst_req ),
    .soc_rsp_o    ( axi_llc_mst_rsp )
  );

endmodule
