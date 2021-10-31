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
//-------------------------------------------------------------------
// Dual port RAM
//-------------------------------------------------------------------
module enet_dp_ram
#(
    parameter WIDTH   = 32
   ,parameter ADDR_W  = 5
)
(
    // Inputs
     input                clk0_i
    ,input  [ADDR_W-1:0]  addr0_i
    ,input  [WIDTH-1:0]   data0_i
    ,input                wr0_i
    ,input                clk1_i
    ,input  [ADDR_W-1:0]  addr1_i
    ,input  [WIDTH-1:0]   data1_i
    ,input                wr1_i

    // Outputs
    ,output [WIDTH-1:0]  data0_o
    ,output [WIDTH-1:0]  data1_o
);

/* verilator lint_off MULTIDRIVEN */
reg [WIDTH-1:0]   ram [(2**ADDR_W)-1:0] /*verilator public*/;
/* verilator lint_on MULTIDRIVEN */

reg [WIDTH-1:0] ram_read0_q;
reg [WIDTH-1:0] ram_read1_q;

// Synchronous write
always @ (posedge clk0_i)
begin
    if (wr0_i)
        ram[addr0_i] <= data0_i;

    ram_read0_q <= ram[addr0_i];
end

always @ (posedge clk1_i)
begin
    if (wr1_i)
        ram[addr1_i] <= data1_i;

    ram_read1_q <= ram[addr1_i];
end

assign data0_o = ram_read0_q;
assign data1_o = ram_read1_q;

endmodule 