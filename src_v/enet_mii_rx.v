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
module enet_mii_rx
(
     input           clk_i
    ,input           rst_i

    ,input  [  3:0]  mii_rxd_i
    ,input           mii_rx_dv_i
    ,input           mii_rx_er_i

    ,input           rd_clk_i
    ,input           rd_rst_i
    ,output          valid_o
    ,output [ 31:0]  data_o
    ,output [ 3:0]   strb_o
    ,output          last_o
    ,output          crc_valid_o
);

localparam NB_PREAMBLE       = 4'h5;
localparam NB_SFD            = 4'hd;

localparam STATE_W           = 2;
localparam STATE_IDLE        = 2'd0;
localparam STATE_WAIT_SFD    = 2'd1;
localparam STATE_FRAME       = 2'd2;
localparam STATE_END         = 2'd3;

reg [STATE_W-1:0]           state_q;
reg [STATE_W-1:0]           next_state_r;

//-----------------------------------------------------------------
// Capture flops
//-----------------------------------------------------------------
reg [3:0] rxd_q;
reg       rx_dv_q;

always @ (posedge clk_i)
    rxd_q <= mii_rxd_i;

always @ (posedge clk_i )
if (rst_i)
    rx_dv_q <= 1'b0;
else
    rx_dv_q <= mii_rx_er_i ? 1'b0 : mii_rx_dv_i;

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
    	// Preamble detected
        if (rx_dv_q)
            next_state_r = STATE_WAIT_SFD;
    end
    //-------------------------------
    // STATE_WAIT_SFD
    //-------------------------------
    STATE_WAIT_SFD : 
    begin
    	// SFD detected
        if (rx_dv_q && rxd_q == NB_SFD)
            next_state_r = STATE_FRAME;
    end
    //-------------------------------
    // STATE_FRAME
    //-------------------------------
    STATE_FRAME :
    begin 
        if (!rx_dv_q)
            next_state_r = STATE_END;
    end
    //-------------------------------
    // STATE_END
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
// Byte reassembly
//-----------------------------------------------------------------
reg rx_toggle_q;

always @ (posedge clk_i )
if (rst_i)
    rx_toggle_q <= 1'b0;
else if (state_q == STATE_WAIT_SFD)
    rx_toggle_q <= 1'b0;
else if (state_q == STATE_FRAME)
    rx_toggle_q <= ~rx_toggle_q;

reg [7:0] rx_data_q;
reg       rx_valid_q;

always @ (posedge clk_i)
    rx_data_q <= {rxd_q ,rx_data_q[7:4]};

always @ (posedge clk_i )
if (rst_i)
    rx_valid_q <= 1'b0;
else if (state_q == STATE_FRAME && rx_dv_q && rx_toggle_q)
    rx_valid_q <= 1'b1;
else
    rx_valid_q <= 1'b0;

wire       rx_valid_w  = rx_valid_q;
wire [7:0] rx_data_w   = rx_data_q;
wire       rx_active_w = (state_q == STATE_FRAME);

//-----------------------------------------------------------------
// CRC check
//-----------------------------------------------------------------
// polynomial: x^32 + x^26 + x^23 + x^22 + x^16 + x^12 + x^11 + x^10 + x^8 + x^7 + x^5 + x^4 + x^2 + x^1 + 1
// data width: 8
// convention: the first serial bit is D[7]
function [31:0] nextCRC32_D8;

input [7:0] Data;
input [31:0] crc;
reg [7:0] d;
reg [31:0] c;
reg [31:0] newcrc;
begin
    d = Data;
    c = crc;

    newcrc[0] = d[6] ^ d[0] ^ c[24] ^ c[30];
    newcrc[1] = d[7] ^ d[6] ^ d[1] ^ d[0] ^ c[24] ^ c[25] ^ c[30] ^ c[31];
    newcrc[2] = d[7] ^ d[6] ^ d[2] ^ d[1] ^ d[0] ^ c[24] ^ c[25] ^ c[26] ^ c[30] ^ c[31];
    newcrc[3] = d[7] ^ d[3] ^ d[2] ^ d[1] ^ c[25] ^ c[26] ^ c[27] ^ c[31];
    newcrc[4] = d[6] ^ d[4] ^ d[3] ^ d[2] ^ d[0] ^ c[24] ^ c[26] ^ c[27] ^ c[28] ^ c[30];
    newcrc[5] = d[7] ^ d[6] ^ d[5] ^ d[4] ^ d[3] ^ d[1] ^ d[0] ^ c[24] ^ c[25] ^ c[27] ^ c[28] ^ c[29] ^ c[30] ^ c[31];
    newcrc[6] = d[7] ^ d[6] ^ d[5] ^ d[4] ^ d[2] ^ d[1] ^ c[25] ^ c[26] ^ c[28] ^ c[29] ^ c[30] ^ c[31];
    newcrc[7] = d[7] ^ d[5] ^ d[3] ^ d[2] ^ d[0] ^ c[24] ^ c[26] ^ c[27] ^ c[29] ^ c[31];
    newcrc[8] = d[4] ^ d[3] ^ d[1] ^ d[0] ^ c[0] ^ c[24] ^ c[25] ^ c[27] ^ c[28];
    newcrc[9] = d[5] ^ d[4] ^ d[2] ^ d[1] ^ c[1] ^ c[25] ^ c[26] ^ c[28] ^ c[29];
    newcrc[10] = d[5] ^ d[3] ^ d[2] ^ d[0] ^ c[2] ^ c[24] ^ c[26] ^ c[27] ^ c[29];
    newcrc[11] = d[4] ^ d[3] ^ d[1] ^ d[0] ^ c[3] ^ c[24] ^ c[25] ^ c[27] ^ c[28];
    newcrc[12] = d[6] ^ d[5] ^ d[4] ^ d[2] ^ d[1] ^ d[0] ^ c[4] ^ c[24] ^ c[25] ^ c[26] ^ c[28] ^ c[29] ^ c[30];
    newcrc[13] = d[7] ^ d[6] ^ d[5] ^ d[3] ^ d[2] ^ d[1] ^ c[5] ^ c[25] ^ c[26] ^ c[27] ^ c[29] ^ c[30] ^ c[31];
    newcrc[14] = d[7] ^ d[6] ^ d[4] ^ d[3] ^ d[2] ^ c[6] ^ c[26] ^ c[27] ^ c[28] ^ c[30] ^ c[31];
    newcrc[15] = d[7] ^ d[5] ^ d[4] ^ d[3] ^ c[7] ^ c[27] ^ c[28] ^ c[29] ^ c[31];
    newcrc[16] = d[5] ^ d[4] ^ d[0] ^ c[8] ^ c[24] ^ c[28] ^ c[29];
    newcrc[17] = d[6] ^ d[5] ^ d[1] ^ c[9] ^ c[25] ^ c[29] ^ c[30];
    newcrc[18] = d[7] ^ d[6] ^ d[2] ^ c[10] ^ c[26] ^ c[30] ^ c[31];
    newcrc[19] = d[7] ^ d[3] ^ c[11] ^ c[27] ^ c[31];
    newcrc[20] = d[4] ^ c[12] ^ c[28];
    newcrc[21] = d[5] ^ c[13] ^ c[29];
    newcrc[22] = d[0] ^ c[14] ^ c[24];
    newcrc[23] = d[6] ^ d[1] ^ d[0] ^ c[15] ^ c[24] ^ c[25] ^ c[30];
    newcrc[24] = d[7] ^ d[2] ^ d[1] ^ c[16] ^ c[25] ^ c[26] ^ c[31];
    newcrc[25] = d[3] ^ d[2] ^ c[17] ^ c[26] ^ c[27];
    newcrc[26] = d[6] ^ d[4] ^ d[3] ^ d[0] ^ c[18] ^ c[24] ^ c[27] ^ c[28] ^ c[30];
    newcrc[27] = d[7] ^ d[5] ^ d[4] ^ d[1] ^ c[19] ^ c[25] ^ c[28] ^ c[29] ^ c[31];
    newcrc[28] = d[6] ^ d[5] ^ d[2] ^ c[20] ^ c[26] ^ c[29] ^ c[30];
    newcrc[29] = d[7] ^ d[6] ^ d[3] ^ c[21] ^ c[27] ^ c[30] ^ c[31];
    newcrc[30] = d[7] ^ d[4] ^ c[22] ^ c[28] ^ c[31];
    newcrc[31] = d[5] ^ c[23] ^ c[29];
    nextCRC32_D8 = newcrc;
end
endfunction

wire [7:0] rev_rx_data_w;

assign rev_rx_data_w[0] = rx_data_w[7-0];
assign rev_rx_data_w[1] = rx_data_w[7-1];
assign rev_rx_data_w[2] = rx_data_w[7-2];
assign rev_rx_data_w[3] = rx_data_w[7-3];
assign rev_rx_data_w[4] = rx_data_w[7-4];
assign rev_rx_data_w[5] = rx_data_w[7-5];
assign rev_rx_data_w[6] = rx_data_w[7-6];
assign rev_rx_data_w[7] = rx_data_w[7-7];

reg [31:0] crc_q;

always @ (posedge clk_i )
if (rst_i)
    crc_q <= {32{1'b1}};
else if (state_q == STATE_WAIT_SFD)
    crc_q <= {32{1'b1}};
else if (rx_valid_w)
    crc_q <= nextCRC32_D8(rev_rx_data_w, crc_q);

wire [31:0] crc_w = ~crc_q;

reg rx_active_q;

always @ (posedge clk_i )
if (rst_i)
    rx_active_q <= 1'b0;
else
    rx_active_q <= rx_active_w;

wire crc_check_w = !rx_active_w && rx_active_q;
wire crc_valid_w = (crc_w == 32'h38FB2284);

//-----------------------------------------------------------------
// Data write index
//-----------------------------------------------------------------
wire       flush_w = !rx_active_w && rx_active_q;

reg [1:0]  idx_q;
always @ (posedge clk_i )
if (rst_i)
    idx_q <= 2'b0;
else if (flush_w)
    idx_q <= 2'b0;
else if (rx_valid_w)
    idx_q <= idx_q + 2'd1;

//-----------------------------------------------------------------
// Data
//-----------------------------------------------------------------
reg [31:0] data_q;
reg [31:0] data_r;

always @ *
begin
    data_r = 32'b0;
    case (idx_q)
    2'd0: data_r = {24'b0,  rx_data_w};
    2'd1: data_r = {16'b0,  rx_data_w, data_q[7:0]};
    2'd2: data_r = {8'b0,   rx_data_w, data_q[15:0]};
    2'd3: data_r = {rx_data_w, data_q[23:0]};
    endcase
end

always @ (posedge clk_i)
if (rx_valid_w)
    data_q <= data_r;

//-----------------------------------------------------------------
// Valid
//-----------------------------------------------------------------
reg valid_q;

always @ (posedge clk_i )
if (rst_i)
    valid_q <= 1'b0;
else if (flush_w && idx_q != 2'd0)
    valid_q <= 1'b1;
else if (rx_valid_w && idx_q == 2'd3)
    valid_q <= 1'b1;
else
    valid_q <= 1'b0;

//-----------------------------------------------------------------
// Mask
//-----------------------------------------------------------------
reg [3:0]  mask_q;

always @ (posedge clk_i)
if (rx_valid_w)
begin
    case (idx_q)
    2'd0: mask_q <= 4'b0001;
    2'd1: mask_q <= mask_q | 4'b0010;
    2'd2: mask_q <= mask_q | 4'b0100;
    2'd3: mask_q <= mask_q | 4'b1000;
    endcase
end

//-----------------------------------------------------------------
// Last
//-----------------------------------------------------------------
wire early_w = (idx_q == 2'b0) && !rx_active_w;

reg last_q;

always @ (posedge clk_i)
    last_q <= !rx_active_w && rx_active_q;

wire last_w = valid_q & (last_q | early_w);

//-----------------------------------------------------------------
// CRC Check
//-----------------------------------------------------------------
reg crc_valid_q;

always @ (posedge clk_i)
if (crc_check_w)
    crc_valid_q <= crc_valid_w;

wire crc_res_w = early_w ? crc_valid_w : crc_valid_q;

//-----------------------------------------------------------------
// CDC
//-----------------------------------------------------------------
wire rd_empty_w;

enet_mii_cdc 
#(
    .WIDTH(32+4+1+1)
)
u_cdc
(
     .wr_clk_i(clk_i)
    ,.wr_rst_i(rst_i)
    ,.wr_push_i(valid_q)
    ,.wr_data_i({crc_res_w, last_w, mask_q, data_q})
    ,.wr_full_o()

    ,.rd_clk_i(rd_clk_i)
    ,.rd_rst_i(rd_rst_i)
    ,.rd_data_o({crc_valid_o, last_o, strb_o, data_o})
    ,.rd_pop_i(1'b1)
    ,.rd_empty_o(rd_empty_w)
);

assign valid_o = ~rd_empty_w;

endmodule
