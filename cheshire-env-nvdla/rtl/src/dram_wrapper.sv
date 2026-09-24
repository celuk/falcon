// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Cyril Koenig <cykoenig@iis.ee.ethz.ch>
// Paul Scheffler <paulsc@iis.ee.ethz.ch>
// Seyyid Hikmet Celik <seyyid4091@gmail.com>
//
// Resize AXI AW, IW, and DW before connecting to a Xilinx DRAM controller.

`include "cheshire/typedef.svh"
`include "common_cells/registers.svh"

`include "header.vh"

module dram_wrapper #(
  parameter type axi_soc_aw_chan_t = logic,
  parameter type axi_soc_w_chan_t  = logic,
  parameter type axi_soc_b_chan_t  = logic,
  parameter type axi_soc_ar_chan_t = logic,
  parameter type axi_soc_r_chan_t  = logic,
  parameter type axi_soc_req_t     = logic,
  parameter type axi_soc_resp_t    = logic
) (
  input  logic  soc_resetn_i,
  input  logic  soc_clk_i,

  input  logic  clk100,
  input  logic  clk_ddr,
  input  logic  clk_ref,
  input  logic  clk_ddr_dqs,
  input  logic  sys_clk_p,
  input  logic  sys_clk_n,

  input  logic        uart_dram_write_we_i,
  input  logic [31:0] uart_dram_write_addr_i,
  input  logic [31:0] uart_dram_write_data_i,
  input  logic        uart_dram_write_rst_i,

  // PHY interfaces

  output        ddr3_ck_p,
  output        ddr3_ck_n,
  `ifdef GENESYS2
  inout  [31:0] ddr3_dq,
  inout  [3:0]  ddr3_dqs_n,
  inout  [3:0]  ddr3_dqs_p,
  output [14:0] ddr3_addr,
  output [2:0]  ddr3_ba,
  output        ddr3_ras_n,
  output        ddr3_cas_n,
  output        ddr3_we_n,
  output        ddr3_reset_n,
  output [0:0]  ddr3_cke,
  output [0:0]  ddr3_cs_n,
  output [3:0]  ddr3_dm,
  output [0:0]  ddr3_odt,
  `elsif ZC706_MIG
  inout  [63:0] ddr3_dq,
  inout  [7:0]  ddr3_dqs_n,
  inout  [7:0]  ddr3_dqs_p,
  output [13:0] ddr3_addr,
  output [2:0]  ddr3_ba,
  output        ddr3_ras_n,
  output        ddr3_cas_n,
  output        ddr3_we_n,
  output        ddr3_reset_n,
  output [0:0]  ddr3_cke,
  output [0:0]  ddr3_cs_n,
  output [7:0]  ddr3_dm,
  output [0:0]  ddr3_odt,
  `else
  inout  [15:0] ddr3_dq,
  inout  [1:0]  ddr3_dqs_n,
  inout  [1:0]  ddr3_dqs_p,
  output [13:0] ddr3_addr,
  output [2:0]  ddr3_ba,
  output        ddr3_ras_n,
  output        ddr3_cas_n,
  output        ddr3_we_n,
  output        ddr3_reset_n,
  output        ddr3_cke,
  output        ddr3_cs_n,
  output [1:0]  ddr3_dm,
  output        ddr3_odt,
  `endif
  // DRAM AXI interface
  input  axi_soc_req_t  soc_req_i,
  output axi_soc_resp_t soc_rsp_o
);

  //////////////////////////////////////
  //  Configurations and definitions  //
  //////////////////////////////////////

  typedef struct packed {
    bit     EnCdc;
    integer CdcLogDepth;
    integer IdWidth;
    integer AddrWidth;
    integer DataWidth;
    integer StrobeWidth;
    integer MaxUniqIds;
    integer MaxTxns;
  } dram_cfg_t;

  localparam dram_cfg_t cfg = '{
    EnCdc         : `ifdef GENESYS2 1 `elsif ZC706_MIG 1 `else 0 `endif,    // 200 MHz AXI (cf. CCdcLogDepth)
    CdcLogDepth   : 5,
    IdWidth       : 4,    // Fixed
    AddrWidth     : 30,
    DataWidth     : 64,
    StrobeWidth   : 8,
    MaxUniqIds    : `ifdef GENESYS2 8 `else 4 `endif,    // TODO: suboptimal, but limited by CVA6/LLC
    MaxTxns       : `ifdef GENESYS2 24 `else 1 `endif    // TODO: suboptimal, but limited by CVA6/LLC
  };

  localparam SocDataWidth = $bits(soc_req_i.w.data);
  localparam SocIdWidth   = $bits(soc_req_i.ar.id);
  localparam SocUserWidth = $bits(soc_req_i.ar.user);
  localparam SocAddrWidth = $bits(soc_req_i.ar.addr);

  // Define type after data width and address resizer
  `AXI_TYPEDEF_ALL(axi_dw, logic[SocAddrWidth-1:0], logic[SocIdWidth-1:0],
                   logic[cfg.DataWidth-1:0], logic[cfg.StrobeWidth-1:0],
                   logic[SocUserWidth-1:0])

  // Define type after data & id width resizers
  `AXI_TYPEDEF_ALL(axi_dw_iw, logic[SocAddrWidth-1:0], logic[cfg.IdWidth-1:0],
                   logic[cfg.DataWidth-1:0], logic[cfg.StrobeWidth-1:0],
                   logic[SocUserWidth-1:0])

  // Clock on which is clocked the DRAM AXI
  logic dram_axi_clk;
  logic dram_rst_o;

  // Signals before resizing
  axi_soc_req_t  soc_dresizer_req;
  axi_soc_resp_t soc_dresizer_rsp;

  // Signals after data width resizing
  axi_dw_req_t  dresizer_iresizer_req;
  axi_dw_resp_t dresizer_iresizer_rsp;

  // Signals after id width resizing
  axi_dw_iw_req_t  iresizer_cdc_req, cdc_dram_req;
  axi_dw_iw_resp_t iresizer_cdc_rsp, cdc_dram_rsp;

  // Entry signals
  assign soc_dresizer_req = soc_req_i;
  assign soc_rsp_o = soc_dresizer_rsp;

  ////////////////////
  //  DW converter  //
  ////////////////////

  axi_dw_converter #(
    .AxiMaxReads          ( cfg.MaxTxns   ),
    .AxiSlvPortDataWidth  ( SocDataWidth  ),
    .AxiMstPortDataWidth  ( cfg.DataWidth ),
    .AxiAddrWidth         ( SocAddrWidth  ),
    .AxiIdWidth           ( SocIdWidth    ),
    // Common AW, AR, B
    .aw_chan_t            ( axi_soc_aw_chan_t ),
    .b_chan_t             ( axi_soc_b_chan_t  ),
    .ar_chan_t            ( axi_soc_ar_chan_t ),
    // Manager W, R
    .mst_w_chan_t         ( axi_dw_w_chan_t ),
    .mst_r_chan_t         ( axi_dw_r_chan_t ),
    .axi_mst_req_t        ( axi_dw_req_t    ),
    .axi_mst_resp_t       ( axi_dw_resp_t   ),
    // Subordinate W, R
    .slv_w_chan_t         ( axi_soc_w_chan_t ),
    .slv_r_chan_t         ( axi_soc_r_chan_t ),
    .axi_slv_req_t        ( axi_soc_req_t  ),
    .axi_slv_resp_t       ( axi_soc_resp_t )
  ) i_axi_dw_converter (
    .clk_i      ( soc_clk_i    ),
    .rst_ni     ( soc_resetn_i ),
    .slv_req_i  ( soc_dresizer_req ),
    .slv_resp_o ( soc_dresizer_rsp ),
    .mst_req_o  ( dresizer_iresizer_req ),
    .mst_resp_i ( dresizer_iresizer_rsp )
  );

  //////////////////
  //  ID resizer  //
  //////////////////

  // TODO: Implement simpler solutions
  axi_iw_converter #(
    .AxiAddrWidth           ( SocAddrWidth  ),
    .AxiDataWidth           ( cfg.DataWidth ),
    .AxiUserWidth           ( SocUserWidth  ),
    .AxiSlvPortIdWidth      ( SocIdWidth    ),
    .AxiSlvPortMaxUniqIds   ( cfg.MaxUniqIds ),
    .AxiSlvPortMaxTxnsPerId ( cfg.MaxTxns    ),
    .AxiSlvPortMaxTxns      ( cfg.MaxTxns    ),
    .AxiMstPortIdWidth      ( cfg.IdWidth    ),
    .AxiMstPortMaxUniqIds   ( cfg.MaxUniqIds ),
    .AxiMstPortMaxTxnsPerId ( cfg.MaxTxns    ),
    .slv_req_t              ( axi_dw_req_t     ),
    .slv_resp_t             ( axi_dw_resp_t    ),
    .mst_req_t              ( axi_dw_iw_req_t  ),
    .mst_resp_t             ( axi_dw_iw_resp_t )
  ) i_axi_iw_converter (
    .clk_i      ( soc_clk_i    ),
    .rst_ni     ( soc_resetn_i ),
    .slv_req_i  ( dresizer_iresizer_req ),
    .slv_resp_o ( dresizer_iresizer_rsp ),
    .mst_req_o  ( iresizer_cdc_req ),
    .mst_resp_i ( iresizer_cdc_rsp )
  );

  ////////////////////////
  //  Instiantiate CDC  //
  ////////////////////////

  `ifdef GENESYS2
  // For MIG targets: intermediate signals between UART MUX and CDC (soc_clk_i domain)
  axi_dw_iw_req_t  pre_cdc_req;
  axi_dw_iw_resp_t pre_cdc_rsp;
  `elsif ZC706_MIG
  // For MIG targets: intermediate signals between UART MUX and CDC (soc_clk_i domain)
  axi_dw_iw_req_t  pre_cdc_req;
  axi_dw_iw_resp_t pre_cdc_rsp;
  `endif

  if (cfg.EnCdc) begin : gen_cdc
    axi_cdc #(
      .aw_chan_t  ( axi_dw_iw_aw_chan_t),
      .w_chan_t   ( axi_dw_iw_w_chan_t),
      .b_chan_t   ( axi_dw_iw_b_chan_t),
      .ar_chan_t  ( axi_dw_iw_ar_chan_t),
      .r_chan_t   ( axi_dw_iw_r_chan_t),
      .axi_req_t  ( axi_dw_iw_req_t),
      .axi_resp_t ( axi_dw_iw_resp_t),
      .LogDepth   ( cfg.CdcLogDepth )
    ) i_axi_cdc_mig (
      .src_clk_i  ( soc_clk_i    ),
      .src_rst_ni ( soc_resetn_i ),
      `ifdef GENESYS2
      .src_req_i  ( pre_cdc_req ),
      .src_resp_o ( pre_cdc_rsp ),
      `elsif ZC706_MIG
      .src_req_i  ( pre_cdc_req ),
      .src_resp_o ( pre_cdc_rsp ),
      `else
      .src_req_i  ( iresizer_cdc_req ),
      .src_resp_o ( iresizer_cdc_rsp ),
      `endif
      .dst_clk_i  ( dram_axi_clk ),
      .dst_rst_ni ( ~dram_rst_o  ),
      .dst_req_o  ( cdc_dram_req ),
      .dst_resp_i ( cdc_dram_rsp )
    );
  end else begin : gen_no_cdc
    assign cdc_dram_req     = iresizer_cdc_req;
    assign iresizer_cdc_rsp = cdc_dram_rsp;
  end

  ////////////////////////////////
  //  Map User, Resize Address  //
  ////////////////////////////////

  assign cdc_dram_rsp.b.user = '0;
  assign cdc_dram_rsp.r.user = '0;

  logic [cfg.AddrWidth-1:0] cdc_dram_req_aw_addr;
  logic [cfg.AddrWidth-1:0] cdc_dram_req_ar_addr;

  assign cdc_dram_req_aw_addr = cdc_dram_req.aw.addr[cfg.AddrWidth-1:0];
  assign cdc_dram_req_ar_addr = cdc_dram_req.ar.addr[cfg.AddrWidth-1:0];

`ifdef GENESYS2
  wire dram_clk_i = clk_ref;
  wire sys_rst_i  = ~soc_resetn_i;
  wire ui_clk;
  wire ui_clk_sync_rst;
  wire init_calib_complete;
  wire mmcm_locked;

  assign dram_axi_clk = ui_clk;
  assign dram_rst_o   = ui_clk_sync_rst;

  // ---------------------------------------------------------
  // FPGA ROM Loader for testing DRAM
  // ---------------------------------------------------------
  logic [31:0] init_rom [0:255];
  initial begin
    $readmemh("../../../cheshire/sw/tests/helloworld.dram.hex", init_rom);
  end

  logic [2:0] calib_sync;
  always_ff @(posedge soc_clk_i) begin
    if (!soc_resetn_i) calib_sync <= '0;
    else calib_sync <= {calib_sync[1:0], init_calib_complete};
  end
  wire calib_done = calib_sync[2];

  logic [8:0] rom_idx;
  logic rom_loading;
  logic rom_we;
  logic [31:0] rom_addr;
  logic [31:0] rom_data;

  typedef enum logic [2:0] { U_IDLE, U_AR, U_R, U_AW, U_W, U_B } uart_st_t;
  uart_st_t u_st;

  reg [29:0] u_addr;
  reg [63:0] u_wdata;
  reg [31:0] u_new_data;
  reg        u_upper;

  always_ff @(posedge soc_clk_i) begin
    if (!soc_resetn_i) begin
      rom_idx <= '0;
      rom_loading <= 1'b1;
      rom_we <= 1'b0;
      rom_addr <= 32'h8000_0000;
      rom_data <= '0;
    end else begin
      rom_we <= 1'b0;
      if (calib_done && rom_loading) begin
        // Wait for UART FSM to be idle and not currently writing
        if (u_st == U_IDLE && !rom_we) begin
          if (rom_idx == 9'd216) begin
            rom_loading <= 1'b0; // Done loading
          end else begin
            rom_we <= 1'b1;
            rom_addr <= 32'h8000_0000 + {21'b0, rom_idx, 2'b00};
            rom_data <= init_rom[rom_idx];
            rom_idx <= rom_idx + 1;
          end
        end
      end
    end
  end

  wire internal_we = uart_dram_write_we_i | rom_we;
  wire [31:0] internal_addr = rom_we ? rom_addr : uart_dram_write_addr_i;
  wire [31:0] internal_data = rom_we ? rom_data : uart_dram_write_data_i;

  always_ff @(posedge soc_clk_i) begin
    if (!soc_resetn_i) begin
      u_st       <= U_IDLE;
      u_addr     <= '0;
      u_wdata    <= '0;
      u_new_data <= '0;
      u_upper    <= '0;
    end else begin
      case (u_st)
        U_IDLE: begin
          if (internal_we) begin
            // 8-byte aligned address for RMW
            u_addr     <= {internal_addr[29:3], 3'b000};
            u_new_data <= internal_data;
            u_upper    <= internal_addr[2];
            u_st       <= U_AR;
          end
        end
        // RMW read phase: issue AXI read
        U_AR: begin
          if (pre_cdc_rsp.ar_ready)
            u_st <= U_R;
        end
        // RMW read phase: capture read data & merge with new 32-bit word
        U_R: begin
          if (pre_cdc_rsp.r_valid) begin
            if (u_upper)
              u_wdata <= {u_new_data, pre_cdc_rsp.r.data[31:0]};
            else
              u_wdata <= {pre_cdc_rsp.r.data[63:32], u_new_data};
            u_st <= U_AW;
          end
        end
        // RMW write phase: issue AXI write address
        U_AW: begin
          if (pre_cdc_rsp.aw_ready)
            u_st <= U_W;
        end
        // RMW write phase: issue AXI write data (full 64-bit, all strobes)
        U_W: begin
          if (pre_cdc_rsp.w_ready)
            u_st <= U_B;
        end
        // RMW write phase: wait for write response
        U_B: begin
          if (pre_cdc_rsp.b_valid)
            u_st <= U_IDLE;
        end
      endcase
    end
  end

  wire uart_active = (u_st != U_IDLE);

  // MUX: UART FSM or SoC (via IW converter) -> CDC input (all on soc_clk_i)
  always_comb begin
    if (uart_active) begin
      pre_cdc_req          = '0;
      // Read address channel (RMW read phase)
      pre_cdc_req.ar_valid = (u_st == U_AR);
      pre_cdc_req.ar.addr  = SocAddrWidth'(u_addr);
      pre_cdc_req.ar.size  = 3'd3;  // 8 bytes
      pre_cdc_req.ar.burst = 2'd1;  // INCR
      // Read data channel
      pre_cdc_req.r_ready  = (u_st == U_R);
      // Write address channel (RMW write phase)
      pre_cdc_req.aw_valid = (u_st == U_AW);
      pre_cdc_req.aw.addr  = SocAddrWidth'(u_addr);
      pre_cdc_req.aw.size  = 3'd3;  // 8 bytes
      pre_cdc_req.aw.burst = 2'd1;  // INCR
      // Write data channel — full 64-bit word, all strobes enabled
      pre_cdc_req.w_valid  = (u_st == U_W);
      pre_cdc_req.w.data   = u_wdata;
      pre_cdc_req.w.strb   = 8'hFF;
      pre_cdc_req.w.last   = 1'b1;
      // Write response channel
      pre_cdc_req.b_ready  = (u_st == U_B);
    end else begin
      pre_cdc_req = iresizer_cdc_req;
    end
  end

  // Route CDC responses back to IW converter
  assign iresizer_cdc_rsp = pre_cdc_rsp;

  // MIG 7 Series — directly connected to CDC output (ui_clk domain)
  mig_7series_0 u_mig_7series_0 (
    // Memory interface ports
    .ddr3_addr                      (ddr3_addr),
    .ddr3_ba                        (ddr3_ba),
    .ddr3_cas_n                     (ddr3_cas_n),
    .ddr3_ck_n                      (ddr3_ck_n),
    .ddr3_ck_p                      (ddr3_ck_p),
    .ddr3_cke                       (ddr3_cke),
    .ddr3_ras_n                     (ddr3_ras_n),
    .ddr3_reset_n                   (ddr3_reset_n),
    .ddr3_we_n                      (ddr3_we_n),
    .ddr3_dq                        (ddr3_dq),
    .ddr3_dqs_n                     (ddr3_dqs_n),
    .ddr3_dqs_p                     (ddr3_dqs_p),
    .init_calib_complete            (init_calib_complete),
    .device_temp                    (),
    .ddr3_cs_n                      (ddr3_cs_n),
    .ddr3_dm                        (ddr3_dm),
    .ddr3_odt                       (ddr3_odt),

    // Application interface ports
    .ui_clk                         (ui_clk),
    .ui_clk_sync_rst                (ui_clk_sync_rst),
    .mmcm_locked                    (mmcm_locked),
    .aresetn                        (soc_resetn_i),
    .app_sr_req                     (1'b0),
    .app_ref_req                    (1'b0),
    .app_zq_req                     (1'b0),
    .app_sr_active                  (),
    .app_ref_ack                    (),
    .app_zq_ack                     (),

    // Slave Interface Write Address Ports
    .s_axi_awid                     (cdc_dram_req.aw.id),
    .s_axi_awaddr                   (cdc_dram_req_aw_addr),
    .s_axi_awlen                    (cdc_dram_req.aw.len),
    .s_axi_awsize                   (cdc_dram_req.aw.size),
    .s_axi_awburst                  (cdc_dram_req.aw.burst),
    .s_axi_awlock                   (cdc_dram_req.aw.lock),
    .s_axi_awcache                  (cdc_dram_req.aw.cache),
    .s_axi_awprot                   (cdc_dram_req.aw.prot),
    .s_axi_awqos                    (cdc_dram_req.aw.qos),
    .s_axi_awvalid                  (cdc_dram_req.aw_valid),
    .s_axi_awready                  (cdc_dram_rsp.aw_ready),

    // Slave Interface Write Data Ports
    .s_axi_wdata                    (cdc_dram_req.w.data),
    .s_axi_wstrb                    (cdc_dram_req.w.strb),
    .s_axi_wlast                    (cdc_dram_req.w.last),
    .s_axi_wvalid                   (cdc_dram_req.w_valid),
    .s_axi_wready                   (cdc_dram_rsp.w_ready),

    // Slave Interface Write Response Ports
    .s_axi_bid                      (cdc_dram_rsp.b.id),
    .s_axi_bresp                    (cdc_dram_rsp.b.resp),
    .s_axi_bvalid                   (cdc_dram_rsp.b_valid),
    .s_axi_bready                   (cdc_dram_req.b_ready),

    // Slave Interface Read Address Ports
    .s_axi_arid                     (cdc_dram_req.ar.id),
    .s_axi_araddr                   (cdc_dram_req_ar_addr),
    .s_axi_arlen                    (cdc_dram_req.ar.len),
    .s_axi_arsize                   (cdc_dram_req.ar.size),
    .s_axi_arburst                  (cdc_dram_req.ar.burst),
    .s_axi_arlock                   (cdc_dram_req.ar.lock),
    .s_axi_arcache                  (cdc_dram_req.ar.cache),
    .s_axi_arprot                   (cdc_dram_req.ar.prot),
    .s_axi_arqos                    (cdc_dram_req.ar.qos),
    .s_axi_arvalid                  (cdc_dram_req.ar_valid),
    .s_axi_arready                  (cdc_dram_rsp.ar_ready),

    // Slave Interface Read Data Ports
    .s_axi_rid                      (cdc_dram_rsp.r.id),
    .s_axi_rdata                    (cdc_dram_rsp.r.data),
    .s_axi_rresp                    (cdc_dram_rsp.r.resp),
    .s_axi_rlast                    (cdc_dram_rsp.r.last),
    .s_axi_rvalid                   (cdc_dram_rsp.r_valid),
    .s_axi_rready                   (cdc_dram_req.r_ready),

    // System Clock Ports
    .sys_clk_i                      (dram_clk_i),
    .sys_rst                        (sys_rst_i)
  );



`elsif ZC706_MIG
  wire sys_rst_i  = ~soc_resetn_i;
  wire ui_clk;
  wire ui_clk_sync_rst;
  wire init_calib_complete;
  wire mmcm_locked;

  assign dram_axi_clk = ui_clk;
  assign dram_rst_o   = ui_clk_sync_rst;

  // ---------------------------------------------------------
  // FPGA ROM Loader for testing DRAM
  // ---------------------------------------------------------
  logic [31:0] init_rom [0:255];
  initial begin
    $readmemh("../../../cheshire/sw/tests/helloworld.dram.hex", init_rom);
  end

  logic [2:0] calib_sync;
  always_ff @(posedge soc_clk_i) begin
    if (!soc_resetn_i) calib_sync <= '0;
    else calib_sync <= {calib_sync[1:0], init_calib_complete};
  end
  wire calib_done = calib_sync[2];

  logic [8:0] rom_idx;
  logic rom_loading;
  logic rom_we;
  logic [31:0] rom_addr;
  logic [31:0] rom_data;

  typedef enum logic [2:0] { U_IDLE, U_AR, U_R, U_AW, U_W, U_B } uart_st_t;
  uart_st_t u_st;

  reg [29:0] u_addr;
  reg [63:0] u_wdata;
  reg [31:0] u_new_data;
  reg        u_upper;

  always_ff @(posedge soc_clk_i) begin
    if (!soc_resetn_i) begin
      rom_idx <= '0;
      rom_loading <= 1'b1;
      rom_we <= 1'b0;
      rom_addr <= 32'h8000_0000;
      rom_data <= '0;
    end else begin
      rom_we <= 1'b0;
      if (calib_done && rom_loading) begin
        // Wait for UART FSM to be idle and not currently writing
        if (u_st == U_IDLE && !rom_we) begin
          if (rom_idx == 9'd216) begin
            rom_loading <= 1'b0; // Done loading
          end else begin
            rom_we <= 1'b1;
            rom_addr <= 32'h8000_0000 + {21'b0, rom_idx, 2'b00};
            rom_data <= init_rom[rom_idx];
            rom_idx <= rom_idx + 1;
          end
        end
      end
    end
  end

  wire internal_we = uart_dram_write_we_i | rom_we;
  wire [31:0] internal_addr = rom_we ? rom_addr : uart_dram_write_addr_i;
  wire [31:0] internal_data = rom_we ? rom_data : uart_dram_write_data_i;

  always_ff @(posedge soc_clk_i) begin
    if (!soc_resetn_i) begin
      u_st       <= U_IDLE;
      u_addr     <= '0;
      u_wdata    <= '0;
      u_new_data <= '0;
      u_upper    <= '0;
    end else begin
      case (u_st)
        U_IDLE: begin
          if (internal_we) begin
            // 8-byte aligned address for RMW
            u_addr     <= {internal_addr[29:3], 3'b000};
            u_new_data <= internal_data;
            u_upper    <= internal_addr[2];
            u_st       <= U_AR;
          end
        end
        // RMW read phase: issue AXI read
        U_AR: begin
          if (pre_cdc_rsp.ar_ready)
            u_st <= U_R;
        end
        // RMW read phase: capture read data & merge with new 32-bit word
        U_R: begin
          if (pre_cdc_rsp.r_valid) begin
            if (u_upper)
              u_wdata <= {u_new_data, pre_cdc_rsp.r.data[31:0]};
            else
              u_wdata <= {pre_cdc_rsp.r.data[63:32], u_new_data};
            u_st <= U_AW;
          end
        end
        // RMW write phase: issue AXI write address
        U_AW: begin
          if (pre_cdc_rsp.aw_ready)
            u_st <= U_W;
        end
        // RMW write phase: issue AXI write data (full 64-bit, all strobes)
        U_W: begin
          if (pre_cdc_rsp.w_ready)
            u_st <= U_B;
        end
        // RMW write phase: wait for write response
        U_B: begin
          if (pre_cdc_rsp.b_valid)
            u_st <= U_IDLE;
        end
      endcase
    end
  end

  wire uart_active = (u_st != U_IDLE);

  // MUX: UART FSM or SoC (via IW converter) -> CDC input (all on soc_clk_i)
  always_comb begin
    if (uart_active) begin
      pre_cdc_req          = '0;
      // Read address channel (RMW read phase)
      pre_cdc_req.ar_valid = (u_st == U_AR);
      pre_cdc_req.ar.addr  = SocAddrWidth'(u_addr);
      pre_cdc_req.ar.size  = 3'd3;  // 8 bytes
      pre_cdc_req.ar.burst = 2'd1;  // INCR
      // Read data channel
      pre_cdc_req.r_ready  = (u_st == U_R);
      // Write address channel (RMW write phase)
      pre_cdc_req.aw_valid = (u_st == U_AW);
      pre_cdc_req.aw.addr  = SocAddrWidth'(u_addr);
      pre_cdc_req.aw.size  = 3'd3;  // 8 bytes
      pre_cdc_req.aw.burst = 2'd1;  // INCR
      // Write data channel — full 64-bit word, all strobes enabled
      pre_cdc_req.w_valid  = (u_st == U_W);
      pre_cdc_req.w.data   = u_wdata;
      pre_cdc_req.w.strb   = 8'hFF;
      pre_cdc_req.w.last   = 1'b1;
      // Write response channel
      pre_cdc_req.b_ready  = (u_st == U_B);
    end else begin
      pre_cdc_req = iresizer_cdc_req;
    end
  end

  // Route CDC responses back to IW converter
  assign iresizer_cdc_rsp = pre_cdc_rsp;

  // MIG 7 Series — directly connected to CDC output (ui_clk domain)
  mig_7series_0 u_mig_7series_0 (
    // Memory interface ports
    .ddr3_addr                      (ddr3_addr),
    .ddr3_ba                        (ddr3_ba),
    .ddr3_cas_n                     (ddr3_cas_n),
    .ddr3_ck_n                      (ddr3_ck_n),
    .ddr3_ck_p                      (ddr3_ck_p),
    .ddr3_cke                       (ddr3_cke),
    .ddr3_ras_n                     (ddr3_ras_n),
    .ddr3_reset_n                   (ddr3_reset_n),
    .ddr3_we_n                      (ddr3_we_n),
    .ddr3_dq                        (ddr3_dq),
    .ddr3_dqs_n                     (ddr3_dqs_n),
    .ddr3_dqs_p                     (ddr3_dqs_p),
    .init_calib_complete            (init_calib_complete),
    .device_temp                    (),
    .ddr3_cs_n                      (ddr3_cs_n),
    .ddr3_dm                        (ddr3_dm),
    .ddr3_odt                       (ddr3_odt),

    // Application interface ports
    .ui_clk                         (ui_clk),
    .ui_clk_sync_rst                (ui_clk_sync_rst),
    .mmcm_locked                    (mmcm_locked),
    .aresetn                        (soc_resetn_i),
    .app_sr_req                     (1'b0),
    .app_ref_req                    (1'b0),
    .app_zq_req                     (1'b0),
    .app_sr_active                  (),
    .app_ref_ack                    (),
    .app_zq_ack                     (),

    // Slave Interface Write Address Ports
    .s_axi_awid                     (cdc_dram_req.aw.id),
    .s_axi_awaddr                   (cdc_dram_req_aw_addr),
    .s_axi_awlen                    (cdc_dram_req.aw.len),
    .s_axi_awsize                   (cdc_dram_req.aw.size),
    .s_axi_awburst                  (cdc_dram_req.aw.burst),
    .s_axi_awlock                   (cdc_dram_req.aw.lock),
    .s_axi_awcache                  (cdc_dram_req.aw.cache),
    .s_axi_awprot                   (cdc_dram_req.aw.prot),
    .s_axi_awqos                    (cdc_dram_req.aw.qos),
    .s_axi_awvalid                  (cdc_dram_req.aw_valid),
    .s_axi_awready                  (cdc_dram_rsp.aw_ready),

    // Slave Interface Write Data Ports
    .s_axi_wdata                    (cdc_dram_req.w.data),
    .s_axi_wstrb                    (cdc_dram_req.w.strb),
    .s_axi_wlast                    (cdc_dram_req.w.last),
    .s_axi_wvalid                   (cdc_dram_req.w_valid),
    .s_axi_wready                   (cdc_dram_rsp.w_ready),

    // Slave Interface Write Response Ports
    .s_axi_bid                      (cdc_dram_rsp.b.id),
    .s_axi_bresp                    (cdc_dram_rsp.b.resp),
    .s_axi_bvalid                   (cdc_dram_rsp.b_valid),
    .s_axi_bready                   (cdc_dram_req.b_ready),

    // Slave Interface Read Address Ports
    .s_axi_arid                     (cdc_dram_req.ar.id),
    .s_axi_araddr                   (cdc_dram_req_ar_addr),
    .s_axi_arlen                    (cdc_dram_req.ar.len),
    .s_axi_arsize                   (cdc_dram_req.ar.size),
    .s_axi_arburst                  (cdc_dram_req.ar.burst),
    .s_axi_arlock                   (cdc_dram_req.ar.lock),
    .s_axi_arcache                  (cdc_dram_req.ar.cache),
    .s_axi_arprot                   (cdc_dram_req.ar.prot),
    .s_axi_arqos                    (cdc_dram_req.ar.qos),
    .s_axi_arvalid                  (cdc_dram_req.ar_valid),
    .s_axi_arready                  (cdc_dram_rsp.ar_ready),

    // Slave Interface Read Data Ports
    .s_axi_rid                      (cdc_dram_rsp.r.id),
    .s_axi_rdata                    (cdc_dram_rsp.r.data),
    .s_axi_rresp                    (cdc_dram_rsp.r.resp),
    .s_axi_rlast                    (cdc_dram_rsp.r.last),
    .s_axi_rvalid                   (cdc_dram_rsp.r_valid),
    .s_axi_rready                   (cdc_dram_req.r_ready),

    // System Clock Ports
    .sys_clk_p                      (sys_clk_p),
    .sys_clk_n                      (sys_clk_n),

    //.sys_clk_i                      (clk_ddr),

    //.clk_ref_i                      (clk_ref),
    
    .sys_rst                        (sys_rst_i)
  );

`else
  assign dram_axi_clk = soc_clk_i;
  assign dram_rst_o   = ~soc_resetn_i;

  dram_controller_axi #(
    .AXI_ID_WIDTH  ( cfg.IdWidth ),
    .AXI_ADDR_WIDTH( cfg.AddrWidth ),
    .AXI_DATA_WIDTH( cfg.DataWidth )
  ) dram_controller (
    .clk_i(soc_clk_i),
    .rst_ni(soc_resetn_i),
    
    .s_axi_awvalid(cdc_dram_req.aw_valid),
    .s_axi_awready(cdc_dram_rsp.aw_ready),
    .s_axi_awaddr(cdc_dram_req_aw_addr),
    .s_axi_awid(cdc_dram_req.aw.id),
    .s_axi_awlen(cdc_dram_req.aw.len),
    .s_axi_awsize(cdc_dram_req.aw.size),
    .s_axi_awburst(cdc_dram_req.aw.burst),
    .s_axi_awprot(cdc_dram_req.aw.prot),

    .s_axi_wvalid(cdc_dram_req.w_valid),
    .s_axi_wready(cdc_dram_rsp.w_ready),
    .s_axi_wdata(cdc_dram_req.w.data),
    .s_axi_wstrb(cdc_dram_req.w.strb),
    .s_axi_wlast(cdc_dram_req.w.last),

    .s_axi_bvalid(cdc_dram_rsp.b_valid),
    .s_axi_bready(cdc_dram_req.b_ready),
    .s_axi_bid(cdc_dram_rsp.b.id),
    .s_axi_bresp(cdc_dram_rsp.b.resp),

    .s_axi_arvalid(cdc_dram_req.ar_valid),
    .s_axi_arready(cdc_dram_rsp.ar_ready),
    .s_axi_araddr(cdc_dram_req_ar_addr),
    .s_axi_arid(cdc_dram_req.ar.id),
    .s_axi_arlen(cdc_dram_req.ar.len),
    .s_axi_arsize(cdc_dram_req.ar.size),
    .s_axi_arburst(cdc_dram_req.ar.burst),
    .s_axi_arprot(cdc_dram_req.ar.prot),

    .s_axi_rvalid(cdc_dram_rsp.r_valid),
    .s_axi_rready(cdc_dram_req.r_ready),
    .s_axi_rid(cdc_dram_rsp.r.id),
    .s_axi_rdata(cdc_dram_rsp.r.data),
    .s_axi_rresp(cdc_dram_rsp.r.resp),
    .s_axi_rlast(cdc_dram_rsp.r.last),

    .ddr3_reset_n(ddr3_reset_n),
    .ddr3_cke(ddr3_cke),
    .ddr3_ck_p(ddr3_ck_p),
    .ddr3_ck_n(ddr3_ck_n),
    .ddr3_cs_n(ddr3_cs_n),
    .ddr3_ras_n(ddr3_ras_n),
    .ddr3_cas_n(ddr3_cas_n),
    .ddr3_we_n(ddr3_we_n),
    .ddr3_ba(ddr3_ba),
    .ddr3_addr(ddr3_addr),
    .ddr3_odt(ddr3_odt),
    .ddr3_dm(ddr3_dm),
    .ddr3_dqs_p(ddr3_dqs_p),
    .ddr3_dqs_n(ddr3_dqs_n),
    .ddr3_dq(ddr3_dq),

    .clk100(clk100),
    .clk_ddr(clk_ddr),
    .clk_ref(clk_ref),
    .clk_ddr_dqs(clk_ddr_dqs),

    .uart_dram_write_we_i(uart_dram_write_we_i),
    .uart_dram_write_addr_i(uart_dram_write_addr_i),
    .uart_dram_write_data_i(uart_dram_write_data_i),
    .uart_dram_write_rst_i(uart_dram_write_rst_i)
  );

`endif

endmodule
