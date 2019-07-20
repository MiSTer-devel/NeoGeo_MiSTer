//============================================================================
//  SNK NeoGeo for MiSTer
//
//  Copyright (C) 2018 Sean 'Furrtek' Gonsalves
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

// Only type 1 is supported for now
// Used by: bangbead ganryu jockeygp nitd pnyaa zupapa

// The exact logic for this is unknown, apparently the NEO-CMC is able to keep track of which
// fix tile is being parsed in the VRAM map just by using nRESET and 12M (and PCK2B ?)
// We're going the easy way here since we can extract the fix map address from LSPC

module cmc_fix(
	//input nRESET,
	//input CLK_12M,
	input PCK2B,
	input [15:0] PBUS,
	input [14:0] FIXMAP_ADDR,
	output reg [1:0] FIX_BANK
);

reg [2:0] BANK_ARRAY[32];

always @(posedge PCK2B)
begin
	if (~FIXMAP_ADDR[0])
	begin
		if (FIXMAP_ADDR[14:6] == 9'b111_0101_00)			// 7500~753F even words
		begin
			// Fix map value == 0200
			BANK_ARRAY[FIXMAP_ADDR[5:1]][2] <= PBUS[9];
		end
		else if (FIXMAP_ADDR[14:6] == 9'b111_0101_10)	// 7580~75BF even words
		begin
			if (BANK_ARRAY[FIXMAP_ADDR[5:1]][2])
			begin
				if (PBUS[11:8] == 4'hF)
					BANK_ARRAY[FIXMAP_ADDR[5:1]][1:0] <= PBUS[1:0];
			end
		end
	end
	
	FIX_BANK <= BANK_ARRAY[FIXMAP_ADDR[4:0]][1:0];
end

endmodule
