// NeoGeo logic definition
// Copyright (C) 2018 Sean Gonsalves
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// Z80 CPU plug into TV80 core

module cpu_z80(
	input CLK_4M,
	input nRESET,
	input [7:0] SDD_IN,
	output [7:0] SDD_OUT,
	output [15:0] SDA,
	output reg nIORQ, nMREQ,
	output reg nRD, nWR,
	input nINT, nNMI
);

	reg [7:0] SDD_IN_REG;
	
	wire [6:0] T_STATE;
	wire [6:0] M_CYCLE;
	wire nINTCYCLE;
	wire NO_READ;
	wire WRITE;
	wire IORQ;

	tv80_core TV80( , IORQ, NO_READ, WRITE, , , , SDA, SDD_OUT, M_CYCLE,
							T_STATE, nINTCYCLE, , , nRESET, CLK_4M, 1'b1, 1'b1,
							nINT, nNMI, 1'b1, SDD_IN, SDD_IN_REG);
	
	always @(posedge CLK_4M)
	begin
		if (!nRESET)
		begin
			nRD <= #1 1'b1;
			nWR <= #1 1'b1;
			nIORQ <= #1 1'b1;
			nMREQ <= #1 1'b1;
			SDD_IN_REG <= #1 8'b00000000;
		end
		else
		begin
			nRD <= #1 1'b1;
			nWR <= #1 1'b1;
			nIORQ <= #1 1'b1;
			nMREQ <= #1 1'b1;
			if (M_CYCLE[0])
			begin
				if (T_STATE[1])
				begin
					nRD <= #1 ~nINTCYCLE;
					nMREQ <= #1 ~nINTCYCLE;
					nIORQ <= #1 nINTCYCLE;
				end
			end
			else
			begin
				if ((T_STATE[1]) && NO_READ == 1'b0 && WRITE == 1'b0)
				begin
					nRD <= #1 1'b0;
					nIORQ <= #1 ~IORQ;
					nMREQ <= #1 IORQ;
				end
				if ((T_STATE[1]) && WRITE == 1'b1)
				begin
					nWR <= #1 1'b0;
					nIORQ <= #1 ~IORQ;
					nMREQ <= #1 IORQ;
				end
			end
			if (T_STATE[2]) SDD_IN_REG <= #1 SDD_IN;
		end
	end
	
endmodule
