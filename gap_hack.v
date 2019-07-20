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

// Sprite graphics gap removal hack

module gap_hack(
	input [19:0] tile,
	input [3:0] C_LATCH,
	input [1:0] map_code,
	output [24:0] CROM_ADDR
);

	// kof95:
	// 1400000-17fffff empty
	// So tiles 28000-2FFFF are normally empty
	// Requested range	Mapped range
	// 00000-27FFF			00000-27FFF (-0)
	// 28000-2FFFF			Empty
	// 30000-33FFF			28000-2BFFF (-8000)
	wire [19:0] tile_kof95 = (tile[17:16] == 2'd3) ? tile - 20'h08000 : tile;

	// whp:
	// 0c00000-0ffffff empty
	// So tiles 18000-1FFFF are normally empty
	// 1400000-17fffff empty
	// So tiles 28000-2FFFF are normally empty
	// Requested range	Mapped range
	// 00000-17FFF			00000-17FFF (-0)
	// 18000-1FFFF			Empty
	// 20000-27FFF			18000-1FFFF (-8000)
	// 28000-2FFFF			Empty
	// 30000-37FFF			20000-27FFF (-8000-8000)
	wire [19:0] tile_whp = (tile[17:16] == 2'd2) ? tile - 20'h08000 :
									(tile[17:16] == 2'd3) ? tile - 20'h10000 :
									tile;

	// kizuna:
	// 0400000-07fffff empty
	// So tiles 08000-0FFFF are normally empty
	// 1400000-17fffff empty
	// So tiles 28000-2FFFF are normally empty
	// Requested range	Mapped range
	// 00000-07FFF			00000-07FFF (-0)
	// 08000-0FFFF			Empty
	// 10000-27FFF			08000-1FFFF (-8000)
	// 28000-2FFFF			Empty
	// 30000-37FFF			20000-27FFF (-8000-8000)
	wire [19:0] tile_kizuna = (tile[17:16] == 2'd1) ? tile - 20'h08000 :
										(tile[17:16] == 2'd3) ? tile - 20'h10000 :
										tile;
	
	wire [19:0] tile_remapped = (map_code == 2'd1) ? tile_kof95 :
											(map_code == 2'd2) ? tile_whp :
											(map_code == 2'd3) ? tile_kizuna :
											tile;
											
	assign CROM_ADDR = {tile_remapped[17:16] + 1'd1, tile_remapped[15:0], C_LATCH[3:0], 3'b000};
	//wire [24:0] CROM_ADDR = {C_LATCH_EXT[1:0] + 1'd1, C_LATCH, 3'b000};
	
endmodule
