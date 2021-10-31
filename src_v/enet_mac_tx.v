//-----------------------------------------------------------------
//               Ethernet MAC 10/100 Mbps Interface
//                            V0.1.0
//               github.com/ultraembedded/core_enet
//                        Copyright 2021
//
//                   admin@ultra-embedded.com
//
//                     License: Apache 2.0
//-----------------------------------------------------------------
// Copyright 2021 github.com/ultraembedded
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//-----------------------------------------------------------------
module enet_mac_tx
(
     input           clk_i
    ,input           rst_i

    ,input           cfg_wr_i
    ,input  [ 31:0]  cfg_addr_i
    ,input  [ 31:0]  cfg_data_wr_i
    ,output [ 31:0]  cfg_data_rd_o

    ,output          glbl_irq_en_o
    ,output          interrupt_o

    ,output          mac_update_o
    ,output [47:0]   mac_addr_o

    ,output          outport_tvalid_o
    ,output [ 31:0]  outport_tdata_o
    ,output [  3:0]  outport_tstrb_o
    ,output          outport_tlast_o
    ,input           outport_tready_i
);

localparam STS_MASK      = 32'h8000001F;
localparam STS_XMIT_IE   = 3;
localparam STS_PROGRAM   = 1;
localparam STS_BUSY      = 0;

//-----------------------------------------------------------------
// GIE
//-----------------------------------------------------------------
reg gie_q;

always @ (posedge clk_i )
if (rst_i)
    gie_q <= 1'b0;
else if (cfg_wr_i && (cfg_addr_i[15:0] == 16'h07F8))
    gie_q <= cfg_data_wr_i[31];

assign glbl_irq_en_o = gie_q;

//-----------------------------------------------------------------
// Tx buffer (2 buffers - 4KB RAM)
//-----------------------------------------------------------------
/* verilator lint_off UNSIGNED */
wire tx_buf_wr_w = cfg_wr_i && (cfg_addr_i[15:0] >= 16'h0000 && cfg_addr_i[15:0] < 16'h1000);
/* verilator lint_on UNSIGNED */

reg  [9:0]  tx_addr_q;
wire [31:0] tx_data_w;

enet_dp_ram
#(
     .WIDTH(32)
    ,.ADDR_W(10)
)
u_tx_ram
(
     .clk0_i(clk_i)
    ,.addr0_i(cfg_addr_i[11:2])
    ,.data0_i(cfg_data_wr_i)
    ,.wr0_i(tx_buf_wr_w)
    ,.data0_o()

    ,.clk1_i(clk_i)
    ,.addr1_i(tx_addr_q)
    ,.data1_i(32'b0)
    ,.wr1_i(1'b0)
    ,.data1_o(tx_data_w)
);

//-----------------------------------------------------------------
// Transmit Length
//-----------------------------------------------------------------
wire txlen0_wr_w = cfg_wr_i && (cfg_addr_i[15:0] == 16'h07F4);

reg [15:0] txlen0_q;

always @ (posedge clk_i )
if (rst_i)
    txlen0_q <= 16'b0;
else if (txlen0_wr_w)
    txlen0_q <= cfg_data_wr_i[15:0];

wire txlen1_wr_w = cfg_wr_i && (cfg_addr_i[15:0] == 16'h0FF4);

reg [15:0] txlen1_q;

always @ (posedge clk_i )
if (rst_i)
    txlen1_q <= 16'b0;
else if (txlen1_wr_w)
    txlen1_q <= cfg_data_wr_i[15:0];

//-----------------------------------------------------------------
// Transmit Control
//-----------------------------------------------------------------
wire       txctl0_wr_w = cfg_wr_i && (cfg_addr_i[15:0] == 16'h07FC);
wire       txctl0_clr_busy_w;
reg [31:0] txctl0_q;

always @ (posedge clk_i )
if (rst_i)
    txctl0_q <= 32'b0;
else if (txctl0_wr_w)
    txctl0_q <= (cfg_data_wr_i & STS_MASK);
else if (txctl0_clr_busy_w)
    txctl0_q <= {txctl0_q[31:2], 2'b0};

wire       txctl1_wr_w = cfg_wr_i && (cfg_addr_i[15:0] == 16'h0FFC);
wire       txctl1_clr_busy_w;
reg [31:0] txctl1_q;

always @ (posedge clk_i )
if (rst_i)
    txctl1_q <= 32'b0;
else if (txctl1_wr_w)
    txctl1_q <= (cfg_data_wr_i & STS_MASK);
else if (txctl1_clr_busy_w)
    txctl1_q <= {txctl1_q[31:2], 2'b0};

wire tx_start0_w = txctl0_q[STS_BUSY];
wire tx_start1_w = txctl1_q[STS_BUSY];

//-----------------------------------------------------------------
// Transmit SM
//-----------------------------------------------------------------
localparam STATE_W           = 2;
localparam STATE_IDLE        = 2'd0;
localparam STATE_READ        = 2'd1;
localparam STATE_WRITE       = 2'd2;
localparam STATE_END         = 2'd3;

reg [STATE_W-1:0]           state_q;
reg [STATE_W-1:0]           next_state_r;
reg [15:0]                  tx_length_q;

//-----------------------------------------------------------------
// Next State Logic
//-----------------------------------------------------------------
always @ *
begin
    next_state_r = state_q;

    case (state_q)
    //-------------------------------
    // STATE_IDLE
    //-------------------------------
    STATE_IDLE : 
    begin
        // Perform action
        if (tx_start0_w || tx_start1_w)
        begin
            // Program MAC address
            if (txctl0_q[STS_PROGRAM] && tx_start0_w)
                next_state_r = STATE_END;
            else if (txctl1_q[STS_PROGRAM] && tx_start1_w)
                next_state_r = STATE_END;
            // Send packet
            else
                next_state_r = STATE_READ;
        end
    end
    //-------------------------------
    // STATE_READ
    //-------------------------------
    STATE_READ : 
    begin
        if (outport_tready_i)
            next_state_r = STATE_WRITE;
    end
    //-------------------------------
    // STATE_WRITE
    //-------------------------------
    STATE_WRITE : 
    begin
        if (tx_length_q == 16'd0)
            next_state_r = STATE_END;
        else
            next_state_r = STATE_READ;
    end
    //-------------------------------
    // STATE_FRAME
    //-------------------------------
    STATE_END :
    begin 
        next_state_r = STATE_IDLE;
    end
    default :
        ;
    endcase
end

// Update state
always @ (posedge clk_i )
if (rst_i)
    state_q <= STATE_IDLE;
else
    state_q <= next_state_r;

//-----------------------------------------------------------------
// Buffer select
//-----------------------------------------------------------------
reg buf_idx_q;

always @ (posedge clk_i )
if (rst_i)
    buf_idx_q <= 1'b0;
else if (state_q == STATE_IDLE)
    buf_idx_q <= tx_start1_w;

//-----------------------------------------------------------------
// Transmit Length
//-----------------------------------------------------------------
wire [15:0] tx_len_w = tx_start0_w ? txlen0_q : txlen1_q;

always @ (posedge clk_i )
if (rst_i)
    tx_length_q <= 16'b0;
else if (state_q == STATE_IDLE)
    tx_length_q <= (tx_len_w < 16'd60) ? 16'd60 : tx_len_w;
else if (state_q == STATE_READ && outport_tready_i)
begin
    if (tx_length_q >= 16'd4)
        tx_length_q <= tx_length_q - 16'd4;
    else
        tx_length_q <= 16'd0;
end

reg [15:0] frame_len_q;

always @ (posedge clk_i )
if (rst_i)
    frame_len_q <= 16'b0;
else if (state_q == STATE_IDLE)
    frame_len_q <= tx_len_w;
else if (state_q == STATE_READ && outport_tready_i)
begin
    if (frame_len_q >= 16'd4)
        frame_len_q <= frame_len_q - 16'd4;
    else
        frame_len_q <= 16'd0;
end

reg padding_q;

always @ (posedge clk_i)
if (state_q == STATE_READ && outport_tready_i)
    padding_q <= (frame_len_q == 16'd0);

assign txctl0_clr_busy_w = (state_q == STATE_END) && ~buf_idx_q;
assign txctl1_clr_busy_w = (state_q == STATE_END) &&  buf_idx_q;

//-----------------------------------------------------------------
// Interrupt Enable
//-----------------------------------------------------------------
reg ie_q;

always @ (posedge clk_i )
if (rst_i)
    ie_q <= 1'b0;
else if (cfg_wr_i && cfg_addr_i[15:0] == 16'h07FC)
    ie_q <= cfg_data_wr_i[3];

//-----------------------------------------------------------------
// Interrupt Output
//-----------------------------------------------------------------
assign interrupt_o = (state_q == STATE_END) ? ie_q : 1'b0;

//-----------------------------------------------------------------
// Transmit Buffer Address
//-----------------------------------------------------------------
always @ (posedge clk_i )
if (rst_i)
    tx_addr_q <= 10'b0;
else if (state_q == STATE_IDLE)
    tx_addr_q <= tx_start0_w ? 10'h000 : 10'h200;
else if (state_q == STATE_READ && outport_tready_i)
    tx_addr_q <= tx_addr_q + 10'd1;

//-----------------------------------------------------------------
// Transmit Output
//-----------------------------------------------------------------
reg [3:0] tx_strb_q;

always @ (posedge clk_i )
if (rst_i)
    tx_strb_q <= 4'hF;
else if (state_q == STATE_READ)
begin
    if (tx_length_q >= 16'd4)
        tx_strb_q <= 4'hF;
    else case (tx_length_q[1:0])
    2'd3:    tx_strb_q <= 4'h7;
    2'd2:    tx_strb_q <= 4'h3;
    default: tx_strb_q <= 4'h1;
    endcase
end

reg tx_last_q;

always @ (posedge clk_i )
if (rst_i)
    tx_last_q <= 1'b0;
else if (state_q == STATE_READ)
    tx_last_q <= (tx_length_q <= 16'd4);

assign outport_tvalid_o = (state_q == STATE_WRITE);
assign outport_tdata_o  = padding_q ? 32'b0 : tx_data_w;
assign outport_tstrb_o  = tx_strb_q;
assign outport_tlast_o  = tx_last_q;

//-----------------------------------------------------------------
// Temporary address storage
//-----------------------------------------------------------------
reg [47:0] tmp_addr_q;

always @ (posedge clk_i)
if (cfg_wr_i && (cfg_addr_i[15:0] == 16'h0000))
    tmp_addr_q[31:0] <= cfg_data_wr_i[31:0];
else if (cfg_wr_i && (cfg_addr_i[15:0] == 16'h0004))
    tmp_addr_q[47:32] <= cfg_data_wr_i[15:0];

assign mac_update_o = (state_q == STATE_IDLE) && txctl0_q[STS_PROGRAM] && tx_start0_w;
assign mac_addr_o   = tmp_addr_q;

//-----------------------------------------------------------------
// Register Read
//-----------------------------------------------------------------
reg [31:0] read_data_r;

always @ *
begin
    read_data_r = 32'b0;

    case (cfg_addr_i[15:0])
    16'h07F8:   read_data_r = {gie_q, 31'b0};
    16'h07F4:   read_data_r = {16'b0, txlen0_q};
    16'h0FF4:   read_data_r = {16'b0, txlen1_q};
    16'h07FC:   read_data_r = {txctl0_q[31:4], ie_q, txctl0_q[2:0]};
    16'h0FFC:   read_data_r = {txctl1_q[31:4], ie_q, txctl1_q[2:0]};
    default: ;
    endcase
end

assign cfg_data_rd_o = read_data_r;

endmodule
