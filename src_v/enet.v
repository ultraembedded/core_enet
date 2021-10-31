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

module enet
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter PROMISCUOUS      = 1
    ,parameter DEFAULT_MAC_ADDR_H = 0
    ,parameter DEFAULT_MAC_ADDR_L = 0
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input  [ 31:0]  cfg_addr_i
    ,input  [ 31:0]  cfg_data_wr_i
    ,input           cfg_stb_i
    ,input           cfg_we_i
    ,input           mii_rx_clk_i
    ,input  [  3:0]  mii_rxd_i
    ,input           mii_rx_dv_i
    ,input           mii_rx_er_i
    ,input           mii_tx_clk_i
    ,input           mii_col_i
    ,input           mii_crs_i

    // Outputs
    ,output [ 31:0]  cfg_data_rd_o
    ,output          cfg_ack_o
    ,output          cfg_stall_o
    ,output          intr_o
    ,output [  3:0]  mii_txd_o
    ,output          mii_tx_en_o
    ,output          mii_reset_n_o
);




//-----------------------------------------------------------------
// MII Interface
//-----------------------------------------------------------------
wire          busy_w;

wire          tx_valid_w;
wire [ 31:0]  tx_data_w;
wire [  3:0]  tx_strb_w;
wire          tx_last_w;
wire          tx_ready_w;

wire          rx_valid_w;
wire [31:0]   rx_data_w;
wire [3:0]    rx_strb_w;
wire          rx_last_w;
wire          rx_crc_valid_w;

enet_mii
u_mii
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.mii_rx_clk_i(mii_rx_clk_i)
    ,.mii_rxd_i(mii_rxd_i)
    ,.mii_rx_dv_i(mii_rx_dv_i)
    ,.mii_rx_er_i(mii_rx_er_i)
    ,.mii_tx_clk_i(mii_tx_clk_i)
    ,.mii_col_i(mii_col_i)
    ,.mii_crs_i(mii_crs_i)
    ,.mii_txd_o(mii_txd_o)
    ,.mii_tx_en_o(mii_tx_en_o)
    ,.mii_reset_n_o(mii_reset_n_o)

    ,.busy_o(busy_w)

    ,.tx_valid_i(tx_valid_w)
    ,.tx_data_i(tx_data_w)
    ,.tx_strb_i(tx_strb_w)
    ,.tx_last_i(tx_last_w)
    ,.tx_accept_o(tx_ready_w)

    ,.rx_valid_o(rx_valid_w)
    ,.rx_data_o(rx_data_w)
    ,.rx_strb_o(rx_strb_w)
    ,.rx_last_o(rx_last_w)
    ,.rx_crc_valid_o(rx_crc_valid_w)
);

//-----------------------------------------------------------------
// Transmit MAC
//-----------------------------------------------------------------
wire [31:0]   tx_cfg_data_rd_w;
wire          tx_interrupt_w;

wire          gie_w;

wire          mac_set_w;
wire [47:0]   mac_addr_w;

enet_mac_tx
u_mac_tx
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.cfg_wr_i(cfg_stb_i && cfg_we_i && !cfg_stall_o)
    ,.cfg_addr_i(cfg_addr_i)
    ,.cfg_data_wr_i(cfg_data_wr_i)
    ,.cfg_data_rd_o(tx_cfg_data_rd_w)

    ,.glbl_irq_en_o(gie_w)

    ,.interrupt_o(tx_interrupt_w)

    ,.mac_update_o(mac_set_w)
    ,.mac_addr_o(mac_addr_w)

    ,.outport_tvalid_o(tx_valid_w)
    ,.outport_tdata_o(tx_data_w)
    ,.outport_tstrb_o(tx_strb_w)
    ,.outport_tlast_o(tx_last_w)
    ,.outport_tready_i(tx_ready_w)
);

//-----------------------------------------------------------------
// MAC Address
//-----------------------------------------------------------------
reg [47:0] mac_addr_q;

always @ (posedge clk_i )
if (rst_i)
    mac_addr_q <= {DEFAULT_MAC_ADDR_H[15:0], DEFAULT_MAC_ADDR_L[31:0]};
else if (mac_set_w)
    mac_addr_q <= mac_addr_w;

//-----------------------------------------------------------------
// Rx
//-----------------------------------------------------------------
wire [31:0] rx_cfg_data_rd_w;
wire [31:0] rx_ram_rd_w;
wire        rx_interrupt_w;

enet_mac_rx
u_mac_rx
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.cfg_wr_i(cfg_stb_i && cfg_we_i && !cfg_stall_o)
    ,.cfg_addr_i(cfg_addr_i)
    ,.cfg_data_wr_i(cfg_data_wr_i)
    ,.cfg_data_rd_o(rx_cfg_data_rd_w)
    ,.ram_data_rd_o(rx_ram_rd_w)

    ,.interrupt_o(rx_interrupt_w)

    ,.promiscuous_i(PROMISCUOUS)
    ,.mac_addr_i(mac_addr_q)

    ,.inport_tvalid_i(rx_valid_w)
    ,.inport_tdata_i(rx_data_w)
    ,.inport_tstrb_i(rx_strb_w)
    ,.inport_tlast_i(rx_last_w)
    ,.inport_crc_valid_i(rx_crc_valid_w)
);

//-----------------------------------------------------------------
// Interrupt Output
//-----------------------------------------------------------------
reg interrupt_q;

always @ (posedge clk_i )
if (rst_i)
    interrupt_q <= 1'b0;
else
    interrupt_q <= gie_w && (tx_interrupt_w || rx_interrupt_w);

assign intr_o = interrupt_q;

//-----------------------------------------------------------------
// Response
//-----------------------------------------------------------------
reg ack_q;

always @ (posedge clk_i )
if (rst_i)
    ack_q <= 1'b0;
else
    ack_q <= cfg_stb_i && !cfg_stall_o;

assign cfg_ack_o   = ack_q;
assign cfg_stall_o = ack_q | busy_w;

reg rd_from_ram_q;

always @ (posedge clk_i )
if (rst_i)
    rd_from_ram_q <= 1'b0;
else if (cfg_stb_i && !cfg_stall_o)
    rd_from_ram_q <= (cfg_addr_i[15:0] >= 16'h1000 && cfg_addr_i[15:0] < 16'h1700) ||
                     (cfg_addr_i[15:0] >= 16'h1800 && cfg_addr_i[15:0] < 16'h1F00);

reg [31:0] data_q;

always @ (posedge clk_i )
if (rst_i)
    data_q <= 32'b0;
else if (cfg_stb_i && !cfg_stall_o && cfg_addr_i[15:0] < 16'h1000)
    data_q <= tx_cfg_data_rd_w;
else if (cfg_stb_i && !cfg_stall_o)
    data_q <= rx_cfg_data_rd_w;

reg [31:0] read_data_r;

always @ *
begin
    read_data_r = 32'b0;

    // Rx RAM
    if (rd_from_ram_q)
        read_data_r = rx_ram_rd_w;
    // Registers
    else
        read_data_r = data_q;
end

assign cfg_data_rd_o = read_data_r;


endmodule
