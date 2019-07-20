//
// ddram.v
// Copyright (c) 2017 Sorgelig
//
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version. 
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// ------------------------------------------
//

// 16-bit version

module ddram
(
	input         DDRAM_CLK,

	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	input  [27:0] wraddr,
	input  [15:0] din,
	input         we_req,
	output reg    we_ack,

	input  [27:1] rdaddr,
	output [15:0] dout,
	input         rd_req,
	output reg    rd_ack
);

assign DDRAM_BURSTCNT = ram_burst;
assign DDRAM_BE       = (8'd3<<{ram_address[2:1],1'b0}) | {8{ram_read}};
assign DDRAM_ADDR     = {4'b0011, ram_address[27:3]}; // RAM at 0x30000000
assign DDRAM_RD       = ram_read;
assign DDRAM_DIN      = ram_data;
assign DDRAM_WE       = ram_write;

assign dout = ram_q[{rdaddr[2:1], 4'b0000} +:16];

reg  [7:0] ram_burst;
reg [63:0] ram_q, next_q;
reg [63:0] ram_data;
reg [27:0] ram_address, cache_addr;
reg        ram_read = 0;
reg        ram_write = 0;

reg [1:0]  state  = 0;

always @(posedge DDRAM_CLK) begin

	if(!DDRAM_BUSY) begin
		ram_write <= 0;
		ram_read  <= 0;

		case(state)
			0: if(we_ack != we_req) begin
					ram_data		<= {4{din}};
					ram_address <= wraddr;
					ram_write 	<= 1;
					ram_burst   <= 1;
					state       <= 1;
				end
				else if(rd_req != rd_ack) begin
					if(cache_addr[27:3] == rdaddr[27:3]) rd_ack <= rd_req;
					else if((cache_addr[27:3]+1'd1) == rdaddr[27:3]) begin
						rd_ack      <= rd_req;
						ram_q       <= next_q;
						cache_addr  <= {rdaddr[27:3],3'b000};
						ram_address <= {rdaddr[27:3]+1'd1,3'b000};
						ram_read    <= 1;
						ram_burst   <= 1;
						state       <= 3;
					end
					else begin
						ram_address <= {rdaddr[27:3],3'b000};
						cache_addr  <= {rdaddr[27:3],3'b000};
						ram_read    <= 1;
						ram_burst   <= 2;
						state       <= 2;
					end 
				end

			1: begin
					cache_addr <= '1;
					cache_addr[3:0] <= 0;
					we_ack <= we_req;
					state  <= 0;
				end
		
			2: if(DDRAM_DOUT_READY) begin
					ram_q  <= DDRAM_DOUT;
					rd_ack <= rd_req;
					state  <= 3;
				end

			3: if(DDRAM_DOUT_READY) begin
					next_q <= DDRAM_DOUT;
					state  <= 0;
				end
		endcase
	end
end

endmodule
