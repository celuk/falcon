// Copyright 2026
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Seyyid Hikmet Celik <seyyid4091@gmail.com>

`timescale 1ns / 1ps

`include "header.vh"
`default_nettype wire

module nvdla_wrapper_axi #(
    parameter int unsigned AXI_ID_WIDTH = 4
)(
    input  wire        clk,
    input  wire        rstn,

    output wire [7:0]  m_axi_awid,
    output wire [63:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,
    output wire [63:0] m_axi_wdata,
    output wire [7:0]  m_axi_wstrb,
    output wire        m_axi_wlast,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,
    input  wire [7:0]  m_axi_bid,
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,
    output wire [7:0]  m_axi_arid,
    output wire [63:0] m_axi_araddr,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [7:0]  m_axi_rid,
    input  wire [63:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready,

    input  wire [AXI_ID_WIDTH-1:0] s_axi_awid,
    input  wire [63:0]             s_axi_awaddr,
    input  wire [7:0]              s_axi_awlen,
    input  wire [2:0]              s_axi_awsize,
    input  wire [1:0]              s_axi_awburst,
    input  wire [2:0]              s_axi_awprot,
    input  wire                    s_axi_awvalid,
    output wire                    s_axi_awready,
    input  wire [63:0]             s_axi_wdata,
    input  wire [7:0]              s_axi_wstrb,
    input  wire                    s_axi_wlast,
    input  wire                    s_axi_wvalid,
    output wire                    s_axi_wready,
    output wire [AXI_ID_WIDTH-1:0] s_axi_bid,
    output wire [1:0]              s_axi_bresp,
    output wire                    s_axi_bvalid,
    input  wire                    s_axi_bready,
    input  wire [AXI_ID_WIDTH-1:0] s_axi_arid,
    input  wire [63:0]             s_axi_araddr,
    input  wire [7:0]              s_axi_arlen,
    input  wire [2:0]              s_axi_arsize,
    input  wire [1:0]              s_axi_arburst,
    input  wire [2:0]              s_axi_arprot,
    input  wire                    s_axi_arvalid,
    output wire                    s_axi_arready,
    output wire [AXI_ID_WIDTH-1:0] s_axi_rid,
    output wire [63:0]             s_axi_rdata,
    output wire [1:0]              s_axi_rresp,
    output wire                    s_axi_rlast,
    output wire                    s_axi_rvalid,
    input  wire                    s_axi_rready,

    output wire        dla_intr
);

    localparam logic [1:0] AXI_BURST_FIXED = 2'b00;
    localparam logic [1:0] AXI_BURST_INCR  = 2'b01;

    wire        psel;
    wire        penable;
    wire        pwrite;
    wire [31:0] paddr;
    wire [31:0] pwdata;
    wire [31:0] prdata;
    wire        pready;
    wire [3:0]  awlen_internal;
    wire [3:0]  arlen_internal;

    nvdla_small nvdla_core (
        .core_clk(clk),
        .csb_clk(clk),
        .rstn(rstn),
        .csb_rstn(rstn),
        .dla_intr(dla_intr),
        .nvdla_core2dbb_aw_awvalid(m_axi_awvalid),
        .nvdla_core2dbb_aw_awready(m_axi_awready),
        .nvdla_core2dbb_aw_awid   (m_axi_awid),
        .nvdla_core2dbb_aw_awlen  (awlen_internal),
        .nvdla_core2dbb_aw_awaddr (m_axi_awaddr),
        .nvdla_core2dbb_w_wvalid  (m_axi_wvalid),
        .nvdla_core2dbb_w_wready  (m_axi_wready),
        .nvdla_core2dbb_w_wdata   (m_axi_wdata),
        .nvdla_core2dbb_w_wstrb   (m_axi_wstrb),
        .nvdla_core2dbb_w_wlast   (m_axi_wlast),
        .nvdla_core2dbb_ar_arvalid(m_axi_arvalid),
        .nvdla_core2dbb_ar_arready(m_axi_arready),
        .nvdla_core2dbb_ar_arid   (m_axi_arid),
        .nvdla_core2dbb_ar_arlen  (arlen_internal),
        .nvdla_core2dbb_ar_araddr (m_axi_araddr),
        .nvdla_core2dbb_b_bvalid  (m_axi_bvalid),
        .nvdla_core2dbb_b_bready  (m_axi_bready),
        .nvdla_core2dbb_b_bid     (m_axi_bid),
        .nvdla_core2dbb_r_rvalid  (m_axi_rvalid),
        .nvdla_core2dbb_r_rready  (m_axi_rready),
        .nvdla_core2dbb_r_rid     (m_axi_rid),
        .nvdla_core2dbb_r_rlast   (m_axi_rlast),
        .nvdla_core2dbb_r_rdata   (m_axi_rdata),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .paddr(paddr),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready)
    );

    assign m_axi_awlen   = {4'b0, awlen_internal};
    assign m_axi_arlen   = {4'b0, arlen_internal};
    assign m_axi_awburst = 2'b01;
    assign m_axi_arburst = 2'b01;
    assign m_axi_awsize  = 3'b011;
    assign m_axi_arsize  = 3'b011;

    typedef enum logic [2:0] {
        S_IDLE,
        S_READ_REQ_APB,
        S_READ_WAIT_APB,
        S_READ_RESP_AXI,
        S_WRITE_WAIT_DATA,
        S_WRITE_REQ_APB,
        S_WRITE_WAIT_APB,
        S_WRITE_RESP_AXI
    } state_e;

    state_e current_state, next_state;

    reg [AXI_ID_WIDTH-1:0]  reg_id;
    reg [63:0]              current_addr;
    reg [7:0]               reg_len;
    reg [2:0]               reg_size;
    reg [1:0]               reg_burst;
    reg [7:0]               beat_count;
    reg                     is_write;
    reg [63:0]              reg_rdata;
    reg [63:0]              apb_wdata;
    reg [7:0]               apb_wstrb;

    assign s_axi_awready = (current_state == S_IDLE);
    assign s_axi_arready = (current_state == S_IDLE);
    assign s_axi_wready  = (current_state == S_WRITE_WAIT_DATA);

    assign s_axi_bvalid  = (current_state == S_WRITE_RESP_AXI);
    assign s_axi_bresp   = 2'b00;
    assign s_axi_bid     = reg_id;

    assign s_axi_rvalid  = (current_state == S_READ_RESP_AXI);
    assign s_axi_rdata   = reg_rdata;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rid     = reg_id;
    assign s_axi_rlast   = (beat_count == reg_len);

    assign psel    = (current_state == S_READ_REQ_APB) || (current_state == S_WRITE_REQ_APB) ||
                     (current_state == S_READ_WAIT_APB) || (current_state == S_WRITE_WAIT_APB);
    assign penable = (current_state == S_READ_WAIT_APB) || (current_state == S_WRITE_WAIT_APB);
    assign pwrite  = is_write;
    assign paddr   = current_addr;
    assign pwdata  = current_addr[2] ? apb_wdata[63:32] : apb_wdata[31:0];

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            current_state <= S_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            reg_id       <= '0;
            current_addr <= '0;
            reg_len      <= '0;
            reg_size     <= '0;
            reg_burst    <= '0;
            beat_count   <= '0;
            is_write     <= 1'b0;
            reg_rdata    <= '0;
            apb_wdata    <= '0;
            apb_wstrb    <= '0;
        end else begin
            case (current_state)
                S_IDLE: begin
                    if (s_axi_awvalid) begin
                        reg_id       <= s_axi_awid;
                        current_addr <= s_axi_awaddr;
                        reg_len      <= s_axi_awlen;
                        reg_size     <= s_axi_awsize;
                        reg_burst    <= s_axi_awburst;
                        is_write     <= 1'b1;
                        beat_count   <= '0;
                    end else if (s_axi_arvalid) begin
                        reg_id       <= s_axi_arid;
                        current_addr <= s_axi_araddr;
                        reg_len      <= s_axi_arlen;
                        reg_size     <= s_axi_arsize;
                        reg_burst    <= s_axi_arburst;
                        is_write     <= 1'b0;
                        beat_count   <= '0;
                    end
                end
                S_WRITE_WAIT_DATA: begin
                    if (s_axi_wvalid) begin
                        apb_wdata <= s_axi_wdata;
                        apb_wstrb <= s_axi_wstrb;
                    end
                end
                S_READ_WAIT_APB: begin
                    if (pready && penable) begin
                        if (current_addr[2]) begin
                            reg_rdata <= {prdata, 32'h0};
                        end else begin
                            reg_rdata <= {32'h0, prdata};
                        end
                    end
                end
                S_READ_RESP_AXI: begin
                    if (s_axi_rready) begin
                        beat_count <= beat_count + 1;
                        if (reg_burst == AXI_BURST_INCR) begin
                            current_addr <= current_addr + (1 << reg_size);
                        end
                    end
                end
                S_WRITE_WAIT_APB: begin
                    if (pready && penable) begin
                        beat_count <= beat_count + 1;
                        if (reg_burst == AXI_BURST_INCR) begin
                            current_addr <= current_addr + (1 << reg_size);
                        end
                    end
                end
            endcase
        end
    end

    always_comb begin
        next_state = current_state;
        case (current_state)
            S_IDLE: begin
                if (s_axi_awvalid) begin
                    next_state = S_WRITE_WAIT_DATA;
                end else if (s_axi_arvalid) begin
                    next_state = S_READ_REQ_APB;
                end
            end
            S_READ_REQ_APB: begin
                next_state = S_READ_WAIT_APB;
            end
            S_READ_WAIT_APB: begin
                if (pready && penable) begin
                    next_state = S_READ_RESP_AXI;
                end
            end
            S_READ_RESP_AXI: begin
                if (s_axi_rready) begin
                    if (beat_count == reg_len) begin
                        next_state = S_IDLE;
                    end else begin
                        next_state = S_READ_REQ_APB;
                    end
                end
            end
            S_WRITE_WAIT_DATA: begin
                if (s_axi_wvalid) begin
                    next_state = S_WRITE_REQ_APB;
                end
            end
            S_WRITE_REQ_APB: begin
                next_state = S_WRITE_WAIT_APB;
            end
            S_WRITE_WAIT_APB: begin
                if (pready && penable) begin
                    if (beat_count == reg_len) begin
                        next_state = S_WRITE_RESP_AXI;
                    end else begin
                        next_state = S_WRITE_WAIT_DATA;
                    end
                end
            end
            S_WRITE_RESP_AXI: begin
                if (s_axi_bready) begin
                    next_state = S_IDLE;
                end
            end
            default: next_state = S_IDLE;
        endcase
    end

endmodule
