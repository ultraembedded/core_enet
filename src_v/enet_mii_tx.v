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
module enet_mii_tx
(
     input           clk_i
    ,input           rst_i

    ,output [  3:0]  mii_txd_o
    ,output          mii_tx_en_o

    ,input           wr_clk_i
    ,input           wr_rst_i
    ,input           valid_i
    ,input  [ 31:0]  data_i
    ,input  [ 3:0]   strb_i
    ,input           last_i
    ,output          accept_o
);

localparam NB_PREAMBLE       = 4'h5;
localparam NB_SFD            = 4'hd;

localparam STATE_W           = 3;
localparam STATE_IDLE        = 3'd0;
localparam STATE_PREAMBLE    = 3'd1;
localparam STATE_SFD         = 3'd2;
localparam STATE_FRAME       = 3'd3;
localparam STATE_CRC         = 3'd4;
localparam STATE_END         = 3'd5;

reg [STATE_W-1:0]           state_q;
reg [STATE_W-1:0]           next_state_r;

reg [7:0]                   state_count_q;

//-----------------------------------------------------------------
// CDC
//-----------------------------------------------------------------
wire        wr_full_w;
wire        rd_empty_w;

wire        tx_ready_w;
wire [31:0] tx_data_w;
wire [3:0]  tx_strb_w;
wire        tx_last_w;
wire        tx_accept_w;

enet_mii_cdc 
#(
    .WIDTH(32+4+1)
)
u_cdc
(
     .wr_clk_i(wr_clk_i)
    ,.wr_rst_i(wr_rst_i)
    ,.wr_push_i(valid_i)
    ,.wr_data_i({last_i, strb_i, data_i})
    ,.wr_full_o(wr_full_w)

    ,.rd_clk_i(clk_i)
    ,.rd_rst_i(rst_i)
    ,.rd_data_o({tx_last_w, tx_strb_w, tx_data_w})
    ,.rd_pop_i(tx_accept_w)
    ,.rd_empty_o(rd_empty_w)
);

assign accept_o    = ~wr_full_w;
assign tx_ready_w  = ~rd_empty_w;
assign tx_accept_w = (state_q == STATE_FRAME && next_state_r == STATE_CRC) ||
                     (state_q == STATE_FRAME && state_count_q[2:0] == 3'd7);

// Xilinx placement pragmas:
//synthesis attribute IOB of mii_txd_q is "TRUE"
//synthesis attribute IOB of mii_tx_en_q is "TRUE"
reg [  3:0]  mii_txd_q;
reg          mii_tx_en_q;

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
        // Something to transmit
        if (tx_ready_w)
            next_state_r = STATE_PREAMBLE;
    end
    //-------------------------------
    // STATE_PREAMBLE
    //-------------------------------
    STATE_PREAMBLE : 
    begin
        // SFD detected
        if (state_count_q == 8'd14)
            next_state_r = STATE_SFD;
    end
    //-------------------------------
    // STATE_SFD
    //-------------------------------
    STATE_SFD : 
    begin
        next_state_r = STATE_FRAME;
    end
    //-------------------------------
    // STATE_FRAME
    //-------------------------------
    STATE_FRAME :
    begin 
        if (tx_last_w)
        begin
            if (tx_strb_w == 4'hF && state_count_q[2:0] == 3'd7)
                next_state_r = STATE_CRC;
            else if (tx_strb_w == 4'h7 && state_count_q[2:0] == 3'd5)
                next_state_r = STATE_CRC;
            else if (tx_strb_w == 4'h3 && state_count_q[2:0] == 3'd3)
                next_state_r = STATE_CRC;
            else if (tx_strb_w == 4'h1 && state_count_q[2:0] == 3'd1)
                next_state_r = STATE_CRC;
        end
    end
    //-------------------------------
    // STATE_CRC
    //-------------------------------
    STATE_CRC :
    begin 
        if (state_count_q == 8'd7)
            next_state_r = STATE_END;
    end
    //-------------------------------
    // STATE_END
    //-------------------------------
    STATE_END :
    begin
        if (state_count_q == 8'd24)
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

always @ (posedge clk_i )
if (rst_i)
    state_count_q <= 8'b0;
else if (state_q != next_state_r || state_q == STATE_IDLE)
    state_count_q <= 8'b0;
else
    state_count_q <= state_count_q + 8'd1;

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

reg       crc_en_r;
reg [7:0] crc_in_r;

always @ *
begin
    case (state_count_q[2:1])
    2'd3:    crc_in_r = tx_data_w[31:24];
    2'd2:    crc_in_r = tx_data_w[23:16];
    2'd1:    crc_in_r = tx_data_w[15:8];
    default: crc_in_r = tx_data_w[7:0];
    endcase

    crc_en_r = state_q == STATE_FRAME && !state_count_q[0];
end

wire [7:0] crc_in_rev_w;
assign crc_in_rev_w[0] = crc_in_r[7-0];
assign crc_in_rev_w[1] = crc_in_r[7-1];
assign crc_in_rev_w[2] = crc_in_r[7-2];
assign crc_in_rev_w[3] = crc_in_r[7-3];
assign crc_in_rev_w[4] = crc_in_r[7-4];
assign crc_in_rev_w[5] = crc_in_r[7-5];
assign crc_in_rev_w[6] = crc_in_r[7-6];
assign crc_in_rev_w[7] = crc_in_r[7-7];

reg [31:0] crc_q;

always @ (posedge clk_i )
if (rst_i)
    crc_q <= {32{1'b1}};
else if (state_q == STATE_SFD)
    crc_q <= {32{1'b1}};
else if (crc_en_r)
    crc_q <= nextCRC32_D8(crc_in_rev_w, crc_q);

wire [31:0] crc_rev_w = ~crc_q;

wire [31:0] crc_w;
assign crc_w[0] = crc_rev_w[31-0];
assign crc_w[1] = crc_rev_w[31-1];
assign crc_w[2] = crc_rev_w[31-2];
assign crc_w[3] = crc_rev_w[31-3];
assign crc_w[4] = crc_rev_w[31-4];
assign crc_w[5] = crc_rev_w[31-5];
assign crc_w[6] = crc_rev_w[31-6];
assign crc_w[7] = crc_rev_w[31-7];
assign crc_w[8] = crc_rev_w[31-8];
assign crc_w[9] = crc_rev_w[31-9];
assign crc_w[10] = crc_rev_w[31-10];
assign crc_w[11] = crc_rev_w[31-11];
assign crc_w[12] = crc_rev_w[31-12];
assign crc_w[13] = crc_rev_w[31-13];
assign crc_w[14] = crc_rev_w[31-14];
assign crc_w[15] = crc_rev_w[31-15];
assign crc_w[16] = crc_rev_w[31-16];
assign crc_w[17] = crc_rev_w[31-17];
assign crc_w[18] = crc_rev_w[31-18];
assign crc_w[19] = crc_rev_w[31-19];
assign crc_w[20] = crc_rev_w[31-20];
assign crc_w[21] = crc_rev_w[31-21];
assign crc_w[22] = crc_rev_w[31-22];
assign crc_w[23] = crc_rev_w[31-23];
assign crc_w[24] = crc_rev_w[31-24];
assign crc_w[25] = crc_rev_w[31-25];
assign crc_w[26] = crc_rev_w[31-26];
assign crc_w[27] = crc_rev_w[31-27];
assign crc_w[28] = crc_rev_w[31-28];
assign crc_w[29] = crc_rev_w[31-29];
assign crc_w[30] = crc_rev_w[31-30];
assign crc_w[31] = crc_rev_w[31-31];

//-----------------------------------------------------------------
// Tx
//-----------------------------------------------------------------
reg       tx_en_r;
reg [3:0] txd_r;

always @ *
begin
    tx_en_r = 1'b0;
    txd_r   = 4'b0;

    case (state_q)
    //-------------------------------
    // STATE_PREAMBLE
    //-------------------------------
    STATE_PREAMBLE : 
    begin
        tx_en_r = 1'b1;
        txd_r   = NB_PREAMBLE;
    end
    //-------------------------------
    // STATE_SFD
    //-------------------------------
    STATE_SFD : 
    begin
        tx_en_r = 1'b1;
        txd_r   = NB_SFD;
    end
    //-------------------------------
    // STATE_FRAME
    //-------------------------------
    STATE_FRAME :
    begin 
        tx_en_r = 1'b1;
        case (state_count_q[2:0])
        3'd7:    txd_r = tx_data_w[31:28];
        3'd6:    txd_r = tx_data_w[27:24];
        3'd5:    txd_r = tx_data_w[23:20];
        3'd4:    txd_r = tx_data_w[19:16];
        3'd3:    txd_r = tx_data_w[15:12];
        3'd2:    txd_r = tx_data_w[11:8];
        3'd1:    txd_r = tx_data_w[7:4];
        default: txd_r = tx_data_w[3:0];
        endcase
    end
    //-------------------------------
    // STATE_CRC
    //-------------------------------
    STATE_CRC :
    begin 
        tx_en_r = 1'b1;
        case (state_count_q[2:0])
        3'd7:    txd_r = crc_w[31:28];
        3'd6:    txd_r = crc_w[27:24];
        3'd5:    txd_r = crc_w[23:20];
        3'd4:    txd_r = crc_w[19:16];
        3'd3:    txd_r = crc_w[15:12];
        3'd2:    txd_r = crc_w[11:8];
        3'd1:    txd_r = crc_w[7:4];
        default: txd_r = crc_w[3:0];
        endcase
    end
    default :
        ;
    endcase
end

always @ (posedge clk_i )
if (rst_i)
    mii_tx_en_q <= 1'b0;
else
    mii_tx_en_q <= tx_en_r;

always @ (posedge clk_i )
if (rst_i)
    mii_txd_q <= 4'b0;
else
    mii_txd_q <= txd_r;

assign mii_tx_en_o = mii_tx_en_q;
assign mii_txd_o   = mii_txd_q;

endmodule
