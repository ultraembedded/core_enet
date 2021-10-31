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
module enet_mac_rx
(
     input           clk_i
    ,input           rst_i

    ,input           promiscuous_i
    ,input  [ 47:0]  mac_addr_i

    ,input           cfg_wr_i
    ,input  [ 31:0]  cfg_addr_i
    ,input  [ 31:0]  cfg_data_wr_i
    ,output [ 31:0]  cfg_data_rd_o

    ,output [ 31:0]  ram_data_rd_o

    ,output          interrupt_o

    ,input           inport_tvalid_i
    ,input  [ 31:0]  inport_tdata_i
    ,input  [  3:0]  inport_tstrb_i
    ,input           inport_tlast_i
    ,input           inport_crc_valid_i
);

//-----------------------------------------------------------------
// Address check
//-----------------------------------------------------------------
reg first_q;

always @ (posedge clk_i )
if (rst_i)
    first_q <= 1'b1;
else if (inport_tvalid_i && inport_tlast_i)
    first_q <= 1'b1;
else  if (inport_tvalid_i)
    first_q <= 1'b0;

reg second_q;

always @ (posedge clk_i )
if (rst_i)
    second_q <= 1'b0;
else if (inport_tvalid_i)
    second_q <= first_q;

reg        valid_q;
reg [31:0] word0_q;
reg [3:0]  strb0_q;
reg        last_q;
reg        crc_ok_q;

always @ (posedge clk_i )
if (rst_i)
    valid_q <= 1'b0;
else if (inport_tvalid_i)
    valid_q <= 1'b1;
else if (valid_q && last_q)
    valid_q <= 1'b0;

always @ (posedge clk_i)
if (inport_tvalid_i)
    word0_q <= inport_tdata_i;

always @ (posedge clk_i)
if (inport_tvalid_i)
    strb0_q <= inport_tstrb_i;

always @ (posedge clk_i)
if (inport_tvalid_i)
    last_q <= inport_tlast_i;

always @ (posedge clk_i)
if (inport_tvalid_i)
    crc_ok_q <= inport_crc_valid_i;

wire        check_da_w = inport_tvalid_i && !first_q && second_q;
wire [47:0] da_w       = {inport_tdata_i[15:0], word0_q};

wire addr_match_w      = promiscuous_i ||
                         (da_w == mac_addr_i) ||
                         (da_w == 48'hFFFFFFFFFFFF);

//-----------------------------------------------------------------
// Space check
//-----------------------------------------------------------------
reg       buf_idx_q;
reg [1:0] ready_q;

wire      has_space_w = ~ready_q[buf_idx_q];

reg       drop_q;
wire      drop_w      = check_da_w ? (!addr_match_w || !has_space_w) : drop_q;
wire      final_w     = valid_q && last_q;

always @ (posedge clk_i )
if (rst_i)
    drop_q <= 1'b0;
else if (check_da_w)
    drop_q <= !addr_match_w || !has_space_w;
else if (final_w)
    drop_q <= 1'b0;

//-----------------------------------------------------------------
// Rx buffer (2 buffers - 4KB RAM)
//-----------------------------------------------------------------
reg  [8:0]  rx_addr_q;

wire valid_w = valid_q && ~drop_w && (inport_tvalid_i || last_q);

enet_dp_ram
#(
     .WIDTH(32)
    ,.ADDR_W(10)
)
u_rx_ram
(
     .clk0_i(clk_i)
    ,.addr0_i({buf_idx_q, rx_addr_q})
    ,.data0_i(word0_q)
    ,.wr0_i(valid_w)
    ,.data0_o()

    ,.clk1_i(clk_i)
    ,.addr1_i(cfg_addr_i[11:2])
    ,.data1_i(32'b0)
    ,.wr1_i(1'b0)
    ,.data1_o(ram_data_rd_o)
);

always @ (posedge clk_i )
if (rst_i)
    rx_addr_q <= 9'b0;
else if (final_w)
    rx_addr_q <= 9'b0;
else if (valid_w)
    rx_addr_q <= rx_addr_q + 9'd1;

always @ (posedge clk_i )
if (rst_i)
    buf_idx_q <= 1'b0;
else if (final_w && !drop_w && crc_ok_q)
    buf_idx_q <= ~buf_idx_q;

//-----------------------------------------------------------------
// Ready flag
//-----------------------------------------------------------------
reg [1:0] ready_r;

always @ *
begin
    ready_r = ready_q;

    if (final_w && !drop_w && crc_ok_q)
        ready_r[buf_idx_q] = 1'b1;

    if (cfg_wr_i && cfg_addr_i[15:0] == 16'h17FC && ~cfg_data_wr_i[0])
        ready_r[0] = 1'b0;

    if (cfg_wr_i && cfg_addr_i[15:0] == 16'h1fFC && ~cfg_data_wr_i[0])
        ready_r[1] = 1'b0;
end

always @ (posedge clk_i )
if (rst_i)
    ready_q <= 2'b0;
else
    ready_q <= ready_r;

//-----------------------------------------------------------------
// Interrupt Enable
//-----------------------------------------------------------------
reg ie_q;

always @ (posedge clk_i )
if (rst_i)
    ie_q <= 1'b0;
else if (cfg_wr_i && cfg_addr_i[15:0] == 16'h17FC)
    ie_q <= cfg_data_wr_i[3];

//-----------------------------------------------------------------
// Interrupt Output
//-----------------------------------------------------------------
assign interrupt_o = (|ready_q) & ie_q;

//-----------------------------------------------------------------
// Register Read
//-----------------------------------------------------------------
reg [31:0] read_data_r;

always @ *
begin
    read_data_r = 32'b0;

    case (cfg_addr_i[15:0])
    16'h17FC:   read_data_r = {28'b0, ie_q, 2'b0, ready_q[0]};
    16'h1FFC:   read_data_r = {28'b0, ie_q, 2'b0, ready_q[1]};
    default: ;
    endcase
end

assign cfg_data_rd_o = read_data_r;

endmodule
