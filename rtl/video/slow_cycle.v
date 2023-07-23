// NeoGeo logic definition
// Copyright (C) 2018 Sean Gonsalves
// Rewrite to fully synchronous logic by (C) 2023 Gyorgy Szombathelyi

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

// Slow VRAM is 120ns (3mclk or more, probably 3.5mclk)

/* verilator lint_off PINMISSING */

module slow_cycle_sync(
	input CLK,
	input CLK_EN_24M_P,
	input LSPC_12M,
	input LSPC_EN_12M_N,
	input LSPC_EN_12M_P,
	input LSPC_6M,
	input LSPC_EN_6M_N,
	input LSPC_3M,
	input LSPC_EN_1_5M_N,
	input RESETP,
	input [14:0] VRAM_ADDR,
	input [15:0] VRAM_WRITE,
	input REG_VRAMADDR_MSB,
	input PIXEL_H8,
	input PIXEL_H8_RISE,
	input PIXEL_H256,
	input [7:3] RASTERC,
	input [3:0] PIXEL_HPLUS,
	input [7:0] ACTIVE_RD,
	input nVRAM_WRITE_REQ,
	input [3:0] SPR_TILEMAP,
	output reg SPR_TILE_VFLIP,
	output reg SPR_TILE_HFLIP,
	output reg SPR_AA_3, SPR_AA_2,
	output [11:0] FIX_TILE,
	output reg [3:0] FIX_PAL,
	output reg [19:0] SPR_TILE,
	output reg [7:0] SPR_PAL,
	output reg [15:0] VRAM_LOW_READ,
	output reg nCPU_WR_LOW,
	input R91_nQ,
	output T160A_OUT,
	output T160B_OUT,
	input CLK_ACTIVE_RD_EN,
	input ACTIVE_RD_PRE8,
	output Q174B_OUT,
	input CLK_SPR_ATTR_EN,
	input SPRITEMAP_ADDR_MSB,
	input CLK_SPR_TILE_EN,
	input P222A_OUT_RISE,
	input P210A_OUT,
	
	output [14:0] SVRAM_ADDR,
	//input [15:0] SVRAM_DATA,
	input [31:0] SVRAM_DATA_IN,
	output [15:0] SVRAM_DATA_OUT,
	output reg BOE, BWE,
	
	output [14:0] FIXMAP_ADDR,		// Extracted for NEO-CMC
	output [14:0] SPRMAP_ADDR,
	output [1:0] VRAM_CYCLE         // Hint to SDRAM controller (10 - Sprite map read, 01 - CPU R/W, 00 - fixmap read)
);

	wire [14:0] B;
	wire [15:0] E;
	reg  [15:0] FIX_MAP_READ;
	//wire [14:0] FIXMAP_ADDR;
	//wire [14:0] SPRMAP_ADDR;
	reg  [3:0] D233_Q;
	reg  [3:0] D283_Q;
	reg  [3:0] Q162_Q;
	
	assign SVRAM_ADDR = B;
	assign E = SVRAM_DATA_IN[15:0];
	assign SVRAM_DATA_OUT = VRAM_WRITE;

	// CPU read
	// H251 F269 F250 D214
	//FDS16bit H251(~CLK_CPU_READ_LOW, E, VRAM_LOW_READ);
	always @(posedge CLK) if (CLK_CPU_READ_LOW_EN) VRAM_LOW_READ <= E;

	// Fix map read
	// E233 C269 B233 B200
	//FDS16bit E233(Q174B_OUT, E, FIX_MAP_READ);
	always @(posedge CLK) if (CLK_SPR_PAL_EN) FIX_MAP_READ <= E;
	assign FIX_TILE = FIX_MAP_READ[11:0];
	//FDSCell E251(~CLK_SPR_TILE, FIX_MAP_READ[15:12], FIX_PAL);
	always @(posedge CLK) if (CLK_SPR_TILE_EN) FIX_PAL <= FIX_MAP_READ[15:12];
	
	// Sprite map read even
	// H233 C279 B250 C191
	`ifdef VRAM32
	//**Gyurco** latch later (same time as even address) to make us of 32 bit VRAM reads
	//FDS16bit H233(D208B_OUT, E, SPR_TILE[15:0]);
	always @(posedge CLK) if (CLK_SPR_ATTR_EN) SPR_TILE[15:0] <= E;
	`else
	//FDS16bit H233(~CLK_SPR_TILE, E, SPR_TILE[15:0]);
	always @(posedge CLK) if (CLK_SPR_TILE_EN) SPR_TILE[15:0] <= E;
	`endif
	
	// Sprite map read odd
	// D233 D283 A249 C201
	`ifdef VRAM32
	//**Gyurco** latch second word from 32-bit read
	//FDS16bit D233(D208B_OUT, SVRAM_DATA_IN[31:16], {D233_Q, D283_Q, SPR_TILE[19:16], SPR_AA_3, SPR_AA_2, SPR_TILE_VFLIP, SPR_TILE_HFLIP});
	always @(posedge CLK) if (CLK_SPR_ATTR_EN) {D233_Q, D283_Q, SPR_TILE[19:16], SPR_AA_3, SPR_AA_2, SPR_TILE_VFLIP, SPR_TILE_HFLIP} <= SVRAM_DATA_IN[31:16];
	`else
	//FDS16bit D233(D208B_OUT, E, {D233_Q, D283_Q, SPR_TILE[19:16], SPR_AA_3, SPR_AA_2, SPR_TILE_VFLIP, SPR_TILE_HFLIP});
	always @(posedge CLK) if (CLK_SPR_ATTR_EN) {D233_Q, D283_Q, SPR_TILE[19:16], SPR_AA_3, SPR_AA_2, SPR_TILE_VFLIP, SPR_TILE_HFLIP} <= E;
	`endif
	//FDSCell C233(Q174B_OUT, D233_Q, SPR_PAL[7:4]);
	//FDSCell D269(Q174B_OUT, D283_Q, SPR_PAL[3:0]);
	always @(posedge CLK) if (CLK_SPR_PAL_EN) SPR_PAL <= {D233_Q, D283_Q};
	
	//assign E = VRAM_LOW_WRITE ? VRAM_WRITE : 16'bzzzzzzzzzzzzzzzz;
	
	// BOE and BWE outputs
	wire Q220_Q, R287A_OUT, R289_nQ;
	//FD2 Q220(CLK_24MB, nCPU_WR_LOW, Q220_Q, BOE);
	always @(posedge CLK) if (CLK_EN_24M_P) BOE <= ~nCPU_WR_LOW;
	//FD2 R289(LSPC_12M, R287A_OUT, BWE, R289_nQ);
	always @(posedge CLK) if (LSPC_EN_12M_N) BWE <= R287A_OUT;
	//assign R287A_OUT = Q220_Q | R289_nQ;
	assign R287A_OUT = ~BOE | ~BWE;
	//assign VRAM_LOW_WRITE = ~BWE;
	
	
	// Address mux
	// E54A F34 F30A
	// F39A J31A H39A H75A
	// F206A I75A E146A N177
	// N179A N182 N172A K169A
	assign B = ~N165_nQ ?
					~N160_Q ? SPRMAP_ADDR : 15'd0
					:
					~N160_Q ? FIXMAP_ADDR : VRAM_ADDR;

	assign VRAM_CYCLE = {~N165_nQ, N160_Q};
	assign FIXMAP_ADDR = {4'b1110, O62_nQ, PIXEL_HPLUS, ~PIXEL_H8, RASTERC[7:3]};
	assign SPRMAP_ADDR = {H57_Q, ACTIVE_RD, O185_Q, SPR_TILEMAP, K166_Q};
	
	wire /*O185_Q, H57_Q, K166_Q, N165_nQ,*/ N169A_OUT/*, N160_Q*/;
	reg O185_Q;
	//FDM O185(P222A_OUT, SPRITEMAP_ADDR_MSB, O185_Q);
	always @(posedge CLK) if (P222A_OUT_RISE) O185_Q <= SPRITEMAP_ADDR_MSB;
	reg H57_Q;
	//FDM H57(CLK_ACTIVE_RD, ACTIVE_RD_PRE8, H57_Q);
	always @(posedge CLK) if (CLK_ACTIVE_RD_EN) H57_Q <= ACTIVE_RD_PRE8;
	//FDM K166(CLK_24M, P210A_OUT, K166_Q);
	//FDM N165(CLK_24M, Q174B_OUT, , N165_nQ);
	//FDM N160(CLK_24M, N169A_OUT, N160_Q);
	reg K166_Q, N165_nQ, N160_Q;
	always @(posedge CLK)
		if (CLK_EN_24M_P) {K166_Q, N165_nQ, N160_Q} <= {P210A_OUT, ~Q174B_OUT, N169A_OUT};
	
	//FS1 Q162(LSPC_12M, R91_nQ, Q162_Q);
	always @(posedge CLK)
		if (LSPC_EN_12M_N) Q162_Q <= {Q162_Q[2:0], ~R91_nQ};
	assign Q174B_OUT = ~Q162_Q[3];
	assign N169A_OUT = ~|{Q174B_OUT, ~CLK_CPU_READ_LOW};
	wire CLK_SPR_PAL_EN = LSPC_EN_12M_N & Q162_Q[3] & ~Q162_Q[2];
	
	//wire T75_Q/*, O62_Q, O62_nQ*/;
	//FDM T75(CLK_24M, T64A_OUT, T75_Q);
	reg T75_Q;
	always @(posedge CLK) if (CLK_EN_24M_P) T75_Q <= T64A_OUT;
	wire   CLK_CPU_READ_LOW = Q162_Q[1];
	wire   CLK_CPU_READ_LOW_EN = LSPC_EN_12M_N & Q162_Q[1] & ~Q162_Q[0];
	assign T160B_OUT = ~|{T75_Q, ~Q162_Q[0]};
	assign T160A_OUT = ~|{Q162_Q[0], T75_Q};
	wire T64A_OUT = ~&{LSPC_12M, LSPC_6M, LSPC_3M};
	
	//FDPCell O62(PIXEL_H8, PIXEL_H256, 1'b1, RESETP, O62_Q, O62_nQ);
	reg O62_nQ;
	always @(posedge CLK)
		if (~RESETP)
			O62_nQ <= 1'b1;
		else if (PIXEL_H8_RISE)
			O62_nQ <= ~PIXEL_H256;
	
	wire F58B_OUT = REG_VRAMADDR_MSB | nVRAM_WRITE_REQ /* synthesis keep */;
	//FDPCell Q106(~LSPC_1_5M, F58B_OUT, CLK_CPU_READ_LOW, 1'b1, nCPU_WR_LOW);
	always @(posedge CLK) 
		if (!CLK_CPU_READ_LOW)
			nCPU_WR_LOW <= 1;
		else if (LSPC_EN_1_5M_N)
			nCPU_WR_LOW <= F58B_OUT;
	
	
	//vram_slow_u VRAMLU(B, E[15:8], 1'b0, BOE, BWE);
	//vram_slow_l VRAMLL(B, E[7:0], 1'b0, BOE, BWE);

endmodule
