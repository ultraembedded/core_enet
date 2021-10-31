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

module enet_mii
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           mii_rx_clk_i
    ,input  [  3:0]  mii_rxd_i
    ,input           mii_rx_dv_i
    ,input           mii_rx_er_i
    ,input           mii_tx_clk_i
    ,input           mii_col_i
    ,input           mii_crs_i
    ,input           tx_valid_i
    ,input  [ 31:0]  tx_data_i
    ,input  [  3:0]  tx_strb_i
    ,input           tx_last_i

    // Outputs
    ,output [  3:0]  mii_txd_o
    ,output          mii_tx_en_o
    ,output          mii_reset_n_o
    ,output          busy_o
    ,output          tx_accept_o
    ,output          rx_valid_o
    ,output [ 31:0]  rx_data_o
    ,output [  3:0]  rx_strb_o
    ,output          rx_last_o
    ,output          rx_crc_valid_o
);



//-----------------------------------------------------------------
// Reset Output
//-----------------------------------------------------------------
localparam RESET_COUNT = 12'd1024;
reg [11:0] rst_cnt_q;

always @ (posedge clk_i )
if (rst_i)
    rst_cnt_q <= 12'b0;
else if (rst_cnt_q < RESET_COUNT)
    rst_cnt_q <= rst_cnt_q + 12'd1;

reg rst_n_q;

always @ (posedge clk_i )
if (rst_i)
    rst_n_q <= 1'b0;
else if (rst_cnt_q == RESET_COUNT)
    rst_n_q <= 1'b1;

assign mii_reset_n_o = rst_n_q;

assign busy_o        = ~rst_n_q;

//-----------------------------------------------------------------
// Rx
//-----------------------------------------------------------------
reg rx_clk_rst_q = 1'b1;

always @ (posedge mii_rx_clk_i)
    rx_clk_rst_q <= 1'b0;

wire        valid_w;
wire [31:0] data_w;
wire        last_w;
wire [3:0]  mask_w;
wire        crc_valid_w;

enet_mii_rx
u_rx
(
     .clk_i(mii_rx_clk_i)
    ,.rst_i(rx_clk_rst_q)

    ,.mii_rxd_i(mii_rxd_i)
    ,.mii_rx_dv_i(mii_rx_dv_i)
    ,.mii_rx_er_i(mii_rx_er_i)

    ,.rd_clk_i(clk_i)
    ,.rd_rst_i(rst_i)
    ,.valid_o(rx_valid_o)
    ,.data_o(rx_data_o)
    ,.strb_o(rx_strb_o)
    ,.last_o(rx_last_o)
    ,.crc_valid_o(rx_crc_valid_o)
);

//-----------------------------------------------------------------
// Tx
//-----------------------------------------------------------------
reg tx_clk_rst_q = 1'b1;

always @ (posedge mii_tx_clk_i)
    tx_clk_rst_q <= 1'b0;

enet_mii_tx
u_tx
(
     .clk_i(mii_tx_clk_i)
    ,.rst_i(tx_clk_rst_q)

    ,.mii_txd_o(mii_txd_o)
    ,.mii_tx_en_o(mii_tx_en_o)

    ,.wr_clk_i(clk_i)
    ,.wr_rst_i(rst_i)

    ,.valid_i(tx_valid_i)
    ,.data_i(tx_data_i)
    ,.strb_i(tx_strb_i)
    ,.last_i(tx_last_i)
    ,.accept_o(tx_accept_o)
);


endmodule
