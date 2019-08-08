//============================================================================
//  NEO-PVC
//
//  Copyright (C) 2019 Alexey Melnikov
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module neo_pvc
(
	input         nRESET,
	input         CLK_24M,

	input  [19:1] M68K_ADDR,
	inout  [15:0] M68K_DATA,
	input  [15:0] PROM_DATA,
	input         nPORTOEL, nPORTOEU,
	input         nPORTWEL, nPORTWEU,

	input         ENABLE,
	output [23:0] P2_ADDR
);

assign P2_ADDR = ENABLE ? bank + {M68K_ADDR,1'b0} : 24'bZ;

assign M68K_DATA[7:0]  = (nPORTOEL | ~ENABLE) ? 8'bZ          :
								             PORT_ACC ? PORT_DO[7:0]  :
								              RAM_ACC ? RAM_DO[7:0]   :
								                        PROM_DATA[7:0];

assign M68K_DATA[15:8] = (nPORTOEU | ~ENABLE) ? 8'bZ           :
								             PORT_ACC ? PORT_DO[15:8]  :
								              RAM_ACC ? RAM_DO[15:8]   :
								                        PROM_DATA[15:8];

wire       RAM_ACC  = ENABLE & &M68K_ADDR[19:13];
wire       PORT_ACC = RAM_ACC && &M68K_ADDR[12:5];
wire [3:0] PORT_NO  = M68K_ADDR[4:1];
wire       nPORTWE  = nPORTWEL & nPORTWEU;

reg [11:0] CLR_ADDR;
always @(posedge CLK_24M) CLR_ADDR <= CLR_ADDR + 1'd1;

wire [15:0] RAM_DO;
dpram #(12) RAML(
	.clock_a(CLK_24M),
	.address_a(M68K_ADDR[12:1]),
	.data_a(M68K_DATA[7:0]),
	.wren_a(RAM_ACC & ~nPORTWEL),
	.q_a(RAM_DO[7:0]),

	.clock_b(CLK_24M),
	.address_b(CLR_ADDR),
	.data_b(CLR_ADDR[7:0]),
	.wren_b(~nRESET)
);

dpram #(12) RAMU(
	.clock_a(CLK_24M),
	.address_a(M68K_ADDR[12:1]),
	.data_a(M68K_DATA[15:8]),
	.wren_a(RAM_ACC & ~nPORTWEU),
	.q_a(RAM_DO[15:8]),

	.clock_b(CLK_24M),
	.address_b(CLR_ADDR),
	.data_b(CLR_ADDR[7:0]),
	.wren_b(~nRESET)
);

reg [23:0] bank = 0;
always @(negedge nPORTWE or negedge nRESET) begin
	if(~nRESET) bank <= 0;
	else begin
		if(PORT_ACC && PORT_NO == 8) bank[7:0]  <= {M68K_DATA[15:9],1'b0};
		if(PORT_ACC && PORT_NO == 9) bank[23:8] <= {1'b0,M68K_DATA[14:0]};
	end
end

reg [4:0] ur,ug,ub;
reg us;
always @(negedge nPORTWE) begin
	if(PORT_ACC && PORT_NO == 0) begin
		ub <= {M68K_DATA[3:0],  M68K_DATA[12]};
		ug <= {M68K_DATA[7:4],  M68K_DATA[13]};
		ur <= {M68K_DATA[11:8], M68K_DATA[14]};
		us <= M68K_DATA[15];
	end
end

reg [15:0] pcol;
always @(negedge nPORTWE) begin
	if(PORT_ACC && PORT_NO == 4) {pcol[13:12],pcol[7:0] } <= {M68K_DATA[8],M68K_DATA[0],M68K_DATA[12:9],M68K_DATA[4:1]};
	if(PORT_ACC && PORT_NO == 5) {pcol[15:14],pcol[11:8]} <= {M68K_DATA[8],M68K_DATA[0],M68K_DATA[4:1]};
end

reg [15:0] PORT_DO;
always @(*) begin
	case(PORT_NO)
			1: PORT_DO = {3'b0,ug,3'b0,ub};
			2: PORT_DO = {7'b0,us,3'b0,ur};
			6: PORT_DO = pcol;
			8: PORT_DO = {bank[7:0], 8'ha0};
			9: PORT_DO = bank[23:8];
	default: PORT_DO = 16'bZ;
	endcase
end

endmodule
