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

// 8-bit version

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

	input     [27:0] rdaddr,
	output reg [7:0] dout,
	input            rd_req,
	output reg       rd_ack,

	input     [27:0] rdaddr2,
	output reg [7:0] dout2,
	input            rd_req2,
	output reg       rd_ack2, 

	input     [27:0] rdaddr3,
	output reg [7:0] dout3,
	input            rd_req3,
	output reg       rd_ack3,

	input     [27:0] cpaddr,
	output reg[63:0] cpdout,
	output reg       cpwr,
	input            cpreq,
	output           cpbusy
);

assign DDRAM_BURSTCNT = ram_burst;
assign DDRAM_BE       = (8'd3<<{ram_address[2:1],1'b0}) | {8{ram_read}};
assign DDRAM_ADDR     = {4'b0011, ram_address[27:3]}; // RAM at 0x30000000
assign DDRAM_RD       = ram_read;
assign DDRAM_DIN      = ram_data;
assign DDRAM_WE       = ram_write;

reg  [7:0] ram_burst;
reg [63:0] ram_q, next_q, ram_q2, next_q2, ram_q3, next_q3;
reg [63:0] ram_data;
reg [27:0] ram_address, cache_addr, cache_addr2, cache_addr3;
reg        ram_read = 0;
reg        ram_write = 0;

reg [2:0]  state  = 0;
reg [1:0]  ch = 0; 

always @(posedge DDRAM_CLK) begin
	reg old_cpreq;
	reg [6:0] cpcnt;

	cpwr <= 0;
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
					if(cache_addr[27:3] == rdaddr[27:3]) begin
						rd_ack      <= rd_req;
						dout        <= ram_q[{rdaddr[2:0],3'b000} +:8];
					end
					else if((cache_addr[27:3]+1'd1) == rdaddr[27:3]) begin
						rd_ack      <= rd_req;
						ram_q       <= next_q;
						dout        <= next_q[{rdaddr[2:0],3'b000} +:8];
						cache_addr  <= {rdaddr[27:3],3'b000};
						ram_address <= {rdaddr[27:3]+1'd1,3'b000};
						ram_read    <= 1;
						ram_burst   <= 1;
						ch 			<= 0; 
						state       <= 3;
					end
					else begin
						ram_address <= {rdaddr[27:3],3'b000};
						cache_addr  <= {rdaddr[27:3],3'b000};
						ram_read    <= 1;
						ram_burst   <= 2;
						ch 			<= 0; 
						state       <= 2;
					end 
				end
				else if(rd_req2 != rd_ack2) begin
					if(cache_addr2[27:3] == rdaddr2[27:3]) begin
						rd_ack2     <= rd_req2;
						dout2       <= ram_q2[{rdaddr2[2:0],3'b000} +:8];
					end
					else if((cache_addr2[27:3]+1'd1) == rdaddr2[27:3]) begin
						rd_ack2     <= rd_req2;
						ram_q2      <= next_q2;
						dout2       <= next_q2[{rdaddr2[2:0],3'b000} +:8];
						cache_addr2 <= {rdaddr2[27:3],3'b000};
						ram_address <= {rdaddr2[27:3]+1'd1,3'b000};
						ram_read    <= 1;
						ram_burst   <= 1;
						ch 			<= 1;
						state       <= 3;
					end
					else begin
						ram_address <= {rdaddr2[27:3],3'b000};
						cache_addr2 <= {rdaddr2[27:3],3'b000};
						ram_read    <= 1;
						ram_burst   <= 2;
						ch 			<= 1;
						state       <= 2;
					end 
				end 
				else if(rd_req3 != rd_ack3) begin
					if(cache_addr3[27:3] == rdaddr3[27:3]) begin
						rd_ack3     <= rd_req3;
						dout3       <= ram_q3[{rdaddr3[2:0],3'b000} +:8];
					end
					else if((cache_addr3[27:3]+1'd1) == rdaddr3[27:3]) begin
						rd_ack3     <= rd_req3;
						ram_q3      <= next_q3;
						dout3       <= next_q3[{rdaddr3[2:0],3'b000} +:8];
						cache_addr3 <= {rdaddr3[27:3],3'b000};
						ram_address <= {rdaddr3[27:3]+1'd1,3'b000};
						ram_read    <= 1;
						ram_burst   <= 1;
						ch 			<= 2;
						state       <= 3;
					end
					else begin
						ram_address <= {rdaddr3[27:3],3'b000};
						cache_addr3 <= {rdaddr3[27:3],3'b000};
						ram_read    <= 1;
						ram_burst   <= 2;
						ch 			<= 2;
						state       <= 2;
					end 
				end else begin
					cpbusy         <= 0;
					old_cpreq <= cpreq;
					if(~old_cpreq & cpreq) begin
						ram_address <= {cpaddr[27:3],3'b000};
						ram_burst   <= 128;
						ram_read    <= 1;
						state       <= 4;
						cpcnt       <= 127;
						cpbusy      <= 1;
					end
				end

			1: begin
					cache_addr <= '1;
					cache_addr2 <= '1; 
					cache_addr3 <= '1; 
					cache_addr[3:0] <= 0;
					cache_addr2[3:0] <= 0; 
					cache_addr3[3:0] <= 0; 
					we_ack <= we_req;
					state  <= 0;
				end

			2: if(DDRAM_DOUT_READY) begin
					if (ch==0) begin
						ram_q  <= DDRAM_DOUT;
						dout   <= DDRAM_DOUT[{rdaddr[2:0],3'b000} +:8];
						rd_ack <= rd_req;
					end
					else if (ch==1) begin
						ram_q2  <= DDRAM_DOUT;
						dout2   <= DDRAM_DOUT[{rdaddr2[2:0],3'b000} +:8];
						rd_ack2 <= rd_req2;
					end 
					else begin
						ram_q3  <= DDRAM_DOUT;
						dout3   <= DDRAM_DOUT[{rdaddr3[2:0],3'b000} +:8];
						rd_ack3 <= rd_req3;
					end 
					state  <= 3;
				end

			3: if(DDRAM_DOUT_READY) begin
					if (ch==0) begin
						next_q <= DDRAM_DOUT;
					end
					else if (ch==1) begin
						next_q2 <= DDRAM_DOUT;
					end 
					else begin
						next_q3 <= DDRAM_DOUT;
					end 
					state  <= 0;
				end

			4: if(DDRAM_DOUT_READY) begin
					cpwr   <= 1;
					cpcnt  <= cpcnt - 1'd1;
					cpdout <= DDRAM_DOUT;
					if(!cpcnt) state <= 0;
				end
		endcase
	end
end

endmodule
