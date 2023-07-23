// NeoGeo logic definition
// Copyright (C) 2018 Sean Gonsalves
// Rewrite to fully synchronous logic by (C) 2023 Gyorgy Szombathelyi
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

module neo_273(
	input CLK,
	input [19:0] PBUS,
	input PCK1B_EN,
	input PCK2B_EN,
	output reg [19:0] C_LATCH,
	output reg [15:0] S_LATCH
);
	always @(posedge CLK) begin
		if (PCK1B_EN) C_LATCH <= {PBUS[15:0], PBUS[19:16]};
		if (PCK2B_EN) S_LATCH <= {PBUS[11:0], PBUS[15:12]};
	end
/*
	always @(posedge PCK1B)
	begin
		C_LATCH <= {PBUS[15:0], PBUS[19:16]};
	end
	
	always @(posedge PCK2B)
	begin
		S_LATCH <= {PBUS[11:0], PBUS[15:12]};
	end
*/
endmodule
