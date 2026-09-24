// Copyright 2026
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Seyyid Hikmet Celik <seyyid4091@gmail.com>

module regwriter #(
    parameter int unsigned AXI_ADDR_WIDTH = 64,
    parameter int unsigned AXI_DATA_WIDTH = 64,
    parameter int unsigned AXI_ID_WIDTH   = 4,
    parameter int unsigned X_ID_WIDTH     = 4  
)(
    input  logic                      clk_i,
    input  logic                      rst_ni,

    // CVXIF Interface
    input  cvxif_pkg::cvxif_req_t     cvxif_req_i,
    output cvxif_pkg::cvxif_resp_t    cvxif_resp_o,

    // AXI Master Interface
    output logic [AXI_ID_WIDTH-1:0]   m_axi_awid,
    output logic [AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output logic [7:0]                m_axi_awlen,
    output logic [2:0]                m_axi_awsize,
    output logic [1:0]                m_axi_awburst,
    output logic                      m_axi_awvalid,
    input  logic                      m_axi_awready,
    output logic [AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output logic [7:0]                m_axi_wstrb,
    output logic                      m_axi_wlast,
    output logic                      m_axi_wvalid,
    input  logic                      m_axi_wready,
    input  logic [AXI_ID_WIDTH-1:0]   m_axi_bid,
    input  logic [1:0]                m_axi_bresp,
    input  logic                      m_axi_bvalid,
    output logic                      m_axi_bready,
    // Read channels (unused)
    output logic [AXI_ID_WIDTH-1:0]   m_axi_arid,
    output logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    output logic [7:0]                m_axi_arlen,
    output logic [2:0]                m_axi_arsize,
    output logic [1:0]                m_axi_arburst,
    output logic                      m_axi_arvalid,
    input  logic                      m_axi_arready,
    input  logic [AXI_ID_WIDTH-1:0]   m_axi_rid,
    input  logic [AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input  logic [1:0]                m_axi_rresp,
    input  logic                      m_axi_rlast,
    input  logic                      m_axi_rvalid,
    output logic                      m_axi_rready
);

    // Unused Read Channels
    assign m_axi_arid    = '0;
    assign m_axi_araddr  = '0;
    assign m_axi_arlen   = '0;
    assign m_axi_arsize  = '0;
    assign m_axi_arburst = '0;
    assign m_axi_arvalid = 1'b0;
    assign m_axi_rready  = 1'b0;

    typedef enum logic [2:0] {
        IDLE,
        WRITE_ADDR,
        WRITE_DATA,
        WAIT_B,
        SEND_RESULT
    } state_t;

    state_t state_q, state_d;
    
    logic [AXI_ADDR_WIDTH-1:0] addr_q, addr_d;
    logic [AXI_DATA_WIDTH-1:0] data_q, data_d;
    logic [X_ID_WIDTH-1:0]     id_q, id_d;
    
    logic is_regw;

    // Encoding: 0000000 | rs2 | rs1 | 000 | 00000 | 1111111
    // regw rs1, rs2 --> Write rs2 data to address in rs1
    assign is_regw = (cvxif_req_i.x_issue_req.instr[6:0] == 7'b1111111) &&
                     (cvxif_req_i.x_issue_req.instr[14:12] == 3'b000) &&
                     (cvxif_req_i.x_issue_req.instr[31:25] == 7'b0000000);

    // Issue Interface
    assign cvxif_resp_o.x_issue_ready = (state_q == IDLE);
    assign cvxif_resp_o.x_issue_resp.accept = is_regw && cvxif_req_i.x_issue_valid;
    assign cvxif_resp_o.x_issue_resp.writeback = 1'b0; // No writeback to RF, we write to AXI
    assign cvxif_resp_o.x_issue_resp.dualwrite = 1'b0;
    assign cvxif_resp_o.x_issue_resp.dualread  = 1'b0;
    assign cvxif_resp_o.x_issue_resp.loadstore = 1'b0;
    assign cvxif_resp_o.x_issue_resp.exc       = 1'b0;
    
    // Result Interface
    assign cvxif_resp_o.x_result_valid = (state_q == SEND_RESULT);
    assign cvxif_resp_o.x_result.id    = id_q;
    assign cvxif_resp_o.x_result.data  = '0;
    assign cvxif_resp_o.x_result.rd    = 5'd0;
    assign cvxif_resp_o.x_result.we    = 1'b0;
    assign cvxif_resp_o.x_result.exc   = 1'b0;
    assign cvxif_resp_o.x_result.exccode = '0;

    assign cvxif_resp_o.x_compressed_ready = 1'b1;
    assign cvxif_resp_o.x_compressed_resp  = '0;
    assign cvxif_resp_o.x_mem_valid        = 1'b0;
    assign cvxif_resp_o.x_mem_req          = '0;

    always_comb begin
        state_d = state_q;
        addr_d  = addr_q;
        data_d  = data_q;
        id_d    = id_q;

        m_axi_awvalid = 1'b0;
        m_axi_awid    = AXI_ID_WIDTH'(id_q); // Propagate CVXIF ID to AXI
        m_axi_awaddr  = addr_q;
        m_axi_awlen   = 8'h00; 
        m_axi_awsize  = 3'b010; // 4 Bytes (32-bit)
        m_axi_awburst = 2'b01; 
        
        m_axi_wvalid  = 1'b0;
        m_axi_wdata   = {data_q[31:0], data_q[31:0]};
        m_axi_wstrb   = addr_q[2] ? 8'hF0 : 8'h0F;
        m_axi_wlast   = 1'b1;
        
        m_axi_bready  = 1'b0;

        case (state_q)
            IDLE: begin
                // x_issue_ready is driven by assign
                if (cvxif_req_i.x_issue_valid && is_regw) begin
                    // rs1 is address(0)
                    addr_d  = cvxif_req_i.x_issue_req.rs[0]; // 64'h40000000 + {44'b0, imm};
                    // rs2 is data(1)
                    data_d  = cvxif_req_i.x_issue_req.rs[1];
                    id_d    = cvxif_req_i.x_issue_req.id;
                    state_d = WRITE_ADDR;
                end
            end

            WRITE_ADDR: begin
                m_axi_awvalid = 1'b1;
                if (m_axi_awready) begin
                    state_d = WRITE_DATA;
                end
            end

            WRITE_DATA: begin
                m_axi_wvalid = 1'b1;
                if (m_axi_wready) begin
                    state_d = WAIT_B;
                end
            end

            WAIT_B: begin
                m_axi_bready = 1'b1;
                if (m_axi_bvalid) begin
                    state_d = SEND_RESULT;
                end
            end

            SEND_RESULT: begin
                if (cvxif_req_i.x_result_ready) begin
                    state_d = IDLE;
                end
            end
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= IDLE;
            addr_q  <= '0;
            data_q  <= '0;
            id_q    <= '0;
        end else begin
            state_q <= state_d;
            addr_q  <= addr_d;
            data_q  <= data_d;
            id_q    <= id_d;
        end
    end

endmodule
