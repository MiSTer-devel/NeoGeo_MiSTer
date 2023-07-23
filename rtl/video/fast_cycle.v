//============================================================================
//  SNK NeoGeo for MiSTer
//
//  Copyright (C) 2018 Sean 'Furrtek' Gonsalves
//  Rewrite to fully synchronous logic by (C) 2023 Gyorgy Szombathelyi

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

/* verilator lint_off PINMISSING */

module fast_cycle_sync(
	input CLK,
	input CLK_24M,
	input CLK_EN_24M_P,
	input CLK_EN_24M_N,
	input LSPC_EN_12M,
	input LSPC_EN_6M,
	input LSPC_EN_3M,
	input LSPC_1_5M,
	input RESETP,
	input nVRAM_WRITE_REQ,
	input [15:0] VRAM_ADDR,
	input [15:0] VRAM_WRITE,
	input REG_VRAMADDR_MSB,
	input FLIP, nFLIP,
	input [8:0] PIXELC,
	input [8:0] RASTERC,
	input P50_CO,
	output reg nCPU_WR_HIGH,
	output [3:0] HSHRINK,
	output [13:0] PIPE_C,
	output reg [15:0] VRAM_HIGH_READ,
	output reg [7:0] ACTIVE_RD,
	output reg R91_Q,
	output reg R91_nQ,
	input T140_Q,
	input T58A_OUT,
	input T73A_OUT,
	input U129A_Q,
	input T125A_OUT,
	input T125A_OUT_RISE,
	output CLK_ACTIVE_RD_EN,
	output reg ACTIVE_RD_PRE8,
	output reg [8:0] SPR_Y,
	output reg [7:0] YSHRINK,
	output reg SPR_SIZE0,
	output reg SPR_SIZE5,
	output O159_QB,
	
	output [10:0] FVRAM_ADDR,
	input [15:0] FVRAM_DATA_IN,
	output [15:0] FVRAM_DATA_OUT,
	output CWE
);

	wire [10:0] C;
	wire [15:0] F;
	reg  [8:0] PARSE_Y;
	reg  [5:0] PARSE_SIZE;
	wire [15:0] F_OUT_MUX;
	reg  [7:0] ACTIVE_RD_PRE;
	wire [3:0] J127_Q;
	reg  [3:0] T102_Q;
	wire [7:0] PARSE_LOOKAHEAD;
	wire [8:0] PARSE_ADD_Y;
	wire [5:0] PARSE_ADD_SIZE;
	reg  [3:0] XSHRINK; //O141_Q
	reg  [7:0] ACTIVE_RD_ADDR;	// Bit 7 unused
	reg  [7:0] ACTIVE_WR_ADDR;	// Bit 7 unused
	wire [10:0] A_TOP;
	wire [10:0] B_TOP;
	wire [10:0] C_TOP;
	wire [10:0] D_TOP;
	wire [10:0] A_BOT;
	wire [10:0] B_BOT;
	wire [10:0] C_BOT;
	wire [10:0] D_BOT;
	reg  PARSE_CHAIN /* synthesis keep */;		// DEBUG
	wire T90A_OUT /* synthesis keep */;			// DEBUG
	reg [8:0] PARSE_INDEX_test;
	reg [8:0] PARSE_INDEX;
	wire P39A_OUT;
	reg [41:0] SR_SPR_PARAMS;	// 3*14
	reg S105_OUT;
	reg [7:0] J87_G152_Q;
	reg J231_Q;
	reg [7:0] J102_E175_Q;
	reg J194_Q;
	
	reg  N98_QC;
	reg  SPR_CHAIN;
	reg  N98_QB;
	reg  N98_QD;
	wire N98_QD_DELAYED;
	reg  O98_Q;
	reg  nPARSING_DONE;
	reg  S111_Q;
	reg  S111_nQ;
	reg  WR_ACTIVE;
	reg  T129A_nQ;
	reg  T66_Q;
	reg  S67_nQ;
	wire S71A_OUT;
	reg  S74_Q;
	reg  T148_Q;
	wire H198_CO;
	reg  N98_QA;
	wire I151_CO;
	
	assign FVRAM_ADDR = C;
	assign F = FVRAM_DATA_IN;
	assign FVRAM_DATA_OUT = F_OUT_MUX;
	
	// CPU read
	// L251 L269 L233 K249
	reg  CLK_CPU_READ_HIGH /* synthesis keep */;
	//FDS16bit L251(~CLK_CPU_READ_HIGH, F, VRAM_HIGH_READ);
	always @(posedge CLK) if (CLK_CPU_READ_HIGH_FALL) VRAM_HIGH_READ <= F;

	// Y parsing read
	// N214 M214 M178 L190
	//FDS16bit N214(O109A_OUT, F, {PARSE_Y, PARSE_CHAIN, PARSE_SIZE});
	always @(posedge CLK) if (O109A_OUT_RISE) {PARSE_Y, PARSE_CHAIN, PARSE_SIZE} <= F;

	// Y Rendering read
	//FDSCell M250(N98_QC, F[15:12], SPR_Y[8:5]);
	//FDSCell M269(N98_QC, F[11:8], SPR_Y[4:1]);
	//FDSCell M233(N98_QC, {F[7:5], F[0]}, {SPR_Y[0], SPR_CHAIN, SPR_SIZE5, SPR_SIZE0});
	always @(posedge CLK) if (N98_QC_RISE) {SPR_Y[8:0], SPR_CHAIN, SPR_SIZE5, SPR_SIZE0} <= {F[15:5], F[0]};

	// Active list read
	//FDSCell J117(H125A_OUT, F[7:4], ACTIVE_RD_PRE[7:4]);
	//FDSCell J178(H125A_OUT, F[3:0], ACTIVE_RD_PRE[3:0]);
	// Next step
	//FDSCell I32(CLK_ACTIVE_RD, ACTIVE_RD_PRE[7:4], ACTIVE_RD[7:4]);
	//FDSCell H165(CLK_ACTIVE_RD, ACTIVE_RD_PRE[3:0], ACTIVE_RD[3:0]);
	always @(posedge CLK)
		if (CLK_ACTIVE_RD_EN) begin
			ACTIVE_RD_PRE[7:0] <= F[7:0];
			ACTIVE_RD_PRE8 <= F[8];
			ACTIVE_RD[7:0] <= ACTIVE_RD_PRE[7:0];
		end
	
	// Shrink read
	//FDSCell O141(N98_QB, F[11:8], O141_Q);
	//FDSCell O123(N98_QB, F[7:4], YSHRINK[7:4]);
	//FDSCell K178(N98_QB, F[3:0], YSHRINK[3:0]);
	always @(posedge CLK) if (N98_QB_RISE) {XSHRINK, YSHRINK} <= F[11:0];

	// Data output selectors
	// O171B O171A O173B O173A
	// B178B B173B B171B C180B
	// C146B C144B C142B C149B
	// E207B E207A E209B E209A
	
	assign F_OUT_MUX = CLK_CPU_READ_HIGH ? VRAM_WRITE : {7'b0000000, J194_Q, J102_E175_Q};
	
	//assign F = CWE ? 16'bzzzzzzzzzzzzzzzz : F_OUT_MUX;
	
	// OK
	//always @(posedge PARSE_INDEX_INC_CLK)
		//{J231_Q, J87_G152_Q} <= PARSE_INDEX;
	always @(posedge CLK) if (PARSE_INDEX_INC_CLK_EN) {J231_Q, J87_G152_Q} <= PARSE_INDEX;
	
	// OK
/*
	always @(posedge O109A_OUT or negedge nPARSING_DONE)
	begin
		if (!nPARSING_DONE)
			{J194_Q, J102_E175_Q} <= 9'd0;
		else
			{J194_Q, J102_E175_Q} <= {J231_Q, J87_G152_Q};
	end
*/
	always @(posedge CLK, negedge nPARSING_DONE)
		if (!nPARSING_DONE) {J194_Q, J102_E175_Q} <= 9'd0;
		else if (O109A_OUT_RISE) {J194_Q, J102_E175_Q} <= {J231_Q, J87_G152_Q};

	//wire O112B_OUT = O109A_OUT;		// 2x inverter
	/*FDSCell G152(PARSE_INDEX_INC_CLK, PARSE_INDEX[3:0], G152_Q);
	//assign #5 G152_Q_DELAYED = G152_Q;	// 4x BD3
	always @(posedge CLK_24M)	// TESTING - ok, solves issue
		G152_Q_DELAYED <= G152_Q;
	FDSCell J87(PARSE_INDEX_INC_CLK, PARSE_INDEX[7:4], J87_Q);
	//assign #5 J87_Q_DELAYED = J87_Q;		// 4x BD3
	always @(posedge CLK_24M)	// TESTING - ok, solves issue
		J87_Q_DELAYED <= J87_Q;
	
	FDRCell E175(O109A_OUT, G152_Q_DELAYED, nPARSING_DONE, E175_Q);
	FDRCell J102(O109A_OUT, J87_Q_DELAYED, nPARSING_DONE, J102_Q);
	FDM J231(PARSE_INDEX_INC_CLK, PARSE_INDEX[8], J231_Q);
	BD3 J235A(J231_Q, J231_Q_DELAYED);
	//always @(posedge CLK_24M)	// TESTED: don't do this
	//	J231_Q_DELAYED <= J231_Q;
	FDPCell J194(O112B_OUT, J231_Q_DELAYED, 1'b1, nPARSING_DONE, J194_Q);*/
	
	
	// CWE output
	wire O107A_OUT = VRAM_HIGH_ADDR_SB & nCPU_WR_HIGH;
	wire T146A_OUT = ~|{T129A_nQ, T148_Q};
	assign CWE = O107A_OUT | T146A_OUT;
	// O103A
	wire VRAM_HIGH_ADDR_SB = ~&{WR_ACTIVE, O98_Q};
	BD3 O84A(N98_QD, N98_QD_DELAYED);
	//FDPCell O98(T125A_OUT, N98_QD_DELAYED, 1'b1, RESETP, O98_Q, CLK_CPU_READ_HIGH);
	always @(posedge CLK, negedge RESETP)
		if (!RESETP) {O98_Q, CLK_CPU_READ_HIGH} <= 2'b01;
		else if (T125A_OUT_RISE) {O98_Q, CLK_CPU_READ_HIGH} <= {N98_QD_DELAYED, ~N98_QD_DELAYED};
	wire CLK_CPU_READ_HIGH_RISE = ~CLK_CPU_READ_HIGH & ~N98_QD_DELAYED & T125A_OUT_RISE;
	wire CLK_CPU_READ_HIGH_FALL =  CLK_CPU_READ_HIGH &  N98_QD_DELAYED & T125A_OUT_RISE;

	//FDPCell N93(N98_QD, F58A_OUT, CLK_CPU_READ_HIGH, 1'b1, nCPU_WR_HIGH);
	always @(posedge CLK)
		if (~CLK_CPU_READ_HIGH) nCPU_WR_HIGH <= 1;
		else if (T125A_OUT_RISE & !N98_QD & N98_QC) nCPU_WR_HIGH <= F58A_OUT;

	
	wire F58A_OUT = ~REG_VRAMADDR_MSB | nVRAM_WRITE_REQ;
	//FDM I148(H125A_OUT, F[8], ACTIVE_RD_PRE8);
	//wire H125A_OUT = CLK_ACTIVE_RD;
	
	
	// Parsing end detection
	// TESTING THIS:
	/*reg nPARSING_DONE;
	always @(posedge O109A_OUT or negedge nNEW_LINE)
	begin
		if (!nNEW_LINE)
			nPARSING_DONE <= 1'b1;
		else
		begin
			if (&{PARSE_INDEX[8], PARSE_INDEX[6:1]})
				nPARSING_DONE <= 1'b0;
		end
	end*/
	wire I145_OUT = ~&{PARSE_INDEX[6:1], PARSE_INDEX[8]};
	wire R113A_OUT = I145_OUT & nPARSING_DONE;
	//FDPCell R109(O109A_OUT, R113A_OUT, nNEW_LINE, 1'b1, nPARSING_DONE);
	always @(posedge CLK, negedge nNEW_LINE)
		if (!nNEW_LINE) nPARSING_DONE <= 1;
		else if (O109A_OUT_RISE) nPARSING_DONE <= R113A_OUT;
	
	// Active list full detection
	/*reg S111_Q;
	wire S111_nQ = ~S111_Q;
	always @(posedge O109A_OUT or negedge nNEW_LINE)
	begin
		if (!nNEW_LINE)
			S111_Q <= 1'b1;
		else
		begin
			if (&{ACTIVE_WR_ADDR[6:5]})
				S111_Q <= 1'b0;
		end
	end*/
	wire S109B_OUT = S111_Q & nACTIVE_FULL;
	//FDPCell S111(O109A_OUT, S109B_OUT, nNEW_LINE, 1'b1, S111_Q, S111_nQ);

	always @(posedge CLK, negedge nNEW_LINE)
		if (!nNEW_LINE) {S111_Q, S111_nQ} <= 2'b10;
		else if (O109A_OUT_RISE) {S111_Q, S111_nQ} <= {S109B_OUT, ~S109B_OUT};

	wire S109A_OUT = S111_Q & nNEW_LINE;
	
	// Write to fast VRAM enable
	wire T95A_OUT = IS_ACTIVE & T102_Q[0];
	wire R107A_OUT = nPARSING_DONE | S111_nQ;
	//FDPCell R103(O109A_OUT, T95A_OUT, R107A_OUT, S109A_OUT, WR_ACTIVE);

	reg WR_ACTIVE_REG;
	always @(*) begin
		if (!R107A_OUT)
			WR_ACTIVE = 1;
		else if (!S109A_OUT)
			WR_ACTIVE = 0;
		else
			WR_ACTIVE = WR_ACTIVE_REG;
	end
	always @(posedge CLK) begin
		WR_ACTIVE_REG <= WR_ACTIVE;
		if (O109A_OUT_RISE) WR_ACTIVE_REG <= T95A_OUT;
	end

	//FD2 T129A(CLK_24M, T126B_OUT, , T129A_nQ);
	always @(posedge CLK) if (CLK_EN_24M_N) T129A_nQ <= ~T126B_OUT;
	wire T126B_OUT = ~&{T66_Q, T140_Q};
	//FDM T66(LSPC_12M, T58A_OUT, T66_Q);
	always @(posedge CLK) if (LSPC_EN_12M) T66_Q <= T58A_OUT;
	
	wire P49A_OUT = PIXELC[8];
	//FDM S67(LSPC_3M, P49A_OUT, , S67_nQ);
	always @(posedge CLK) if (LSPC_EN_3M) S67_nQ <= ~P49A_OUT;
	wire S70B_OUT = ~&{S67_nQ, P49A_OUT};
	BD3 S71A(S70B_OUT, S71A_OUT);
	//FDM S74(LSPC_6M, S71A_OUT, S74_Q);
	always @(posedge CLK) if (LSPC_EN_6M) S74_Q <= S71A_OUT;
	// S107A Used for test mode
	wire nNEW_LINE = 1'b1 & S74_Q /* synthesis keep */;
	
	//FDM T148(CLK_24M, T128B_OUT, T148_Q);
	always @(posedge CLK) if (CLK_EN_24M_P) T148_Q <= T128B_OUT;
	wire T128B_OUT = ~&{T73A_OUT, U129A_Q};
	
	// T181A
	wire IS_ACTIVE = PARSE_CHAIN ? T90A_OUT : M176A_OUT;
	
	wire M176A_OUT = PARSE_MATCH | PARSE_SIZE[5];
	//BD3 S105(VRAM_HIGH_ADDR_SB, S105_OUT);
	always @(posedge CLK/*_24M*/)
		S105_OUT <= VRAM_HIGH_ADDR_SB;	// TESTING - ok, solves issue
	//FDRCell T102(O109A_OUT, {1'b0, T102_Q[1], T102_Q[0], S105_OUT}, nNEW_LINE, T102_Q);
	always @(posedge CLK, negedge nNEW_LINE)
		if (!nNEW_LINE)
			T102_Q <= 0;
		else if (O109A_OUT_RISE)
			T102_Q <= {1'b0, T102_Q[1], T102_Q[0], S105_OUT};

	wire T94_OUT = ~&{T102_Q[1:0], O102B_OUT};
	wire T92_OUT = ~&{~T102_Q[2], ~T102_Q[1], T102_Q[0], VRAM_HIGH_ADDR_SB};
	assign T90A_OUT = ~&{T94_OUT, T92_OUT};
	/*
	always @(posedge O110B_OUT or negedge nNEW_LINE)
	begin
		if (!nNEW_LINE)
			ACTIVE_WR_ADDR <= 0;
		else
			ACTIVE_WR_ADDR <= ACTIVE_WR_ADDR + 1'd1;
	end
	*/
	always @(posedge CLK, negedge nNEW_LINE)
		if (!nNEW_LINE)
			ACTIVE_WR_ADDR <= 0;
		else if (O110B_OUT_RISE)
			ACTIVE_WR_ADDR <= ACTIVE_WR_ADDR + 1'd1;
	/*
	C43 H198(O110B_OUT, 4'b0000, 1'b1, 1'b1, 1'b1, nNEW_LINE, ACTIVE_WR_ADDR[3:0], H198_CO);
	// Used for test mode
	wire H222A_OUT = H198_CO | 1'b0;
	C43 I189(O110B_OUT, 4'b0000, 1'b1, 1'b1, H222A_OUT, nNEW_LINE, ACTIVE_WR_ADDR[7:4]);
	*/
	//wire O110B_OUT = O109A_OUT | VRAM_HIGH_ADDR_SB;
	wire O110B_OUT_RISE = O109A_OUT_RISE & ~VRAM_HIGH_ADDR_SB;
	wire nACTIVE_FULL = ~&{ACTIVE_WR_ADDR[6:5]};	// J100B
	
	
	//FS3 N98(T125A_OUT, 4'b0000, R91_nQ, RESETP, {N98_QD, N98_QC, N98_QB, N98_QA});
	always @(posedge CLK)
		if (!RESETP) {N98_QD, N98_QC, N98_QB, N98_QA} <= 0;
		else if (T125A_OUT_RISE) {N98_QD, N98_QC, N98_QB, N98_QA} <= {N98_QC, N98_QB, N98_QA, R91_nQ};
	//assign CLK_ACTIVE_RD = ~K131B_OUT;
	assign CLK_ACTIVE_RD_EN = T125A_OUT_RISE & ~N98_QA & R91_nQ;

	wire N98_QB_RISE = T125A_OUT_RISE & !N98_QB & N98_QA;
	wire N98_QC_RISE = T125A_OUT_RISE & !N98_QC & N98_QB;
	wire N98_QD_RISE = T125A_OUT_RISE & !N98_QD & N98_QC;

	//FDM R91(LSPC_12M, LSPC_1_5M, R91_Q, R91_nQ);
	always @(posedge CLK) if (LSPC_EN_12M) {R91_Q, R91_nQ} <= {LSPC_1_5M, ~LSPC_1_5M};
	
	// Address mux
	// I213 I218 G169A G164 G182A G194A G200 G205A I175A I182A
	// J62 J72A I104 I109A J205A J200 J49 J54A H28A H34 I13 I18A
	assign A_TOP = {N98_QC, J36_OUT, ACTIVE_RD_PRE8, ACTIVE_RD_PRE};
	assign B_TOP = {3'b110, H293B_OUT, ACTIVE_RD_ADDR[6:0]};
	assign C_TOP = {3'b110, H293B_OUT, ACTIVE_RD_ADDR[6:0]};
	assign D_TOP = {N98_QC, J36_OUT, ACTIVE_RD_PRE8, ACTIVE_RD_PRE};
	
	assign A_BOT = {3'b110, I237A_OUT, ACTIVE_WR_ADDR[6:0]};
	assign B_BOT = VRAM_ADDR[10:0];
	assign C_BOT = VRAM_ADDR[10:0];
	assign D_BOT = {2'b01, PARSE_INDEX};
	
	// L110B_OUT  A
	// ~VRAM_HIGH_ADDR_SB B
	// M95B_OUT   C
	// ABC:
	assign C = 	M95B_OUT ?
						~VRAM_HIGH_ADDR_SB ?
							L110B_OUT ? C_TOP : A_TOP		// 111 - 110
						:
							L110B_OUT ? B_TOP : D_TOP		// 101 - 100
					:
						~VRAM_HIGH_ADDR_SB ?
							L110B_OUT ? C_BOT : A_BOT		// 011 - 010
						:
							L110B_OUT ? B_BOT : D_BOT;		// 001 - 000
/*
	assign C = 	L110B_OUT ?
						~VRAM_HIGH_ADDR_SB ?
							M95B_OUT ? C_TOP : A_TOP		// 111 - 110
						:
							M95B_OUT ? B_TOP : D_TOP		// 101 - 100
					:
						~VRAM_HIGH_ADDR_SB ?
							M95B_OUT ? C_BOT : A_BOT		// 011 - 010
						:
							M95B_OUT ? B_BOT : D_BOT;		// 001 - 000
							*/
	
	wire K131B_OUT = ~N98_QA;
	wire M95B_OUT = ~|{N98_QD, O98_Q};
	wire L110B_OUT = ~|{L110A_OUT, O98_Q};
	wire L110A_OUT = ~|{K131B_OUT, N98_QD};
	wire I237A_OUT = FLIP;
	wire K260B_OUT = FLIP;
	wire H293B_OUT = nFLIP;
	wire J36_OUT = N98_QB ^ N98_QC;
	
	// Active list read counter
	
	assign #1 P39A_OUT = ~PIXELC[8];
	//always @(posedge CLK_24M)	// TESTING
		//P39A_OUT <= ~PIXELC[8];
	wire nRELOAD_RD_ACTIVE = ~&{PIXELC[6], P50_CO, P39A_OUT};	// O55A
	//C43 I151(CLK_ACTIVE_RD, 4'b0000, nRELOAD_RD_ACTIVE, 1'b1, 1'b1, 1'b1, ACTIVE_RD_ADDR[3:0], I151_CO);
	//wire J176A_OUT = I151_CO | 1'b0;	// Used for test mode
	//C43 J151(CLK_ACTIVE_RD, 4'b0000, nRELOAD_RD_ACTIVE, 1'b1, J176A_OUT, 1'b1, ACTIVE_RD_ADDR[7:4]);
	always @(posedge CLK)
		if (CLK_ACTIVE_RD_EN) begin
			if (!nRELOAD_RD_ACTIVE)
				ACTIVE_RD_ADDR <= 0;
			else
				ACTIVE_RD_ADDR <= ACTIVE_RD_ADDR + 1'd1;
		end
	
	
	// OK
	// Parsing counter
	/*
	always @(posedge PARSE_INDEX_INC_CLK or negedge nNEW_LINE)
	begin
		if (!nNEW_LINE)
			PARSE_INDEX_test <= 9'd0;
		else
			PARSE_INDEX_test <= PARSE_INDEX_test + 1'd1;
	end*/
	always @(posedge CLK, negedge nNEW_LINE)
		if (!nNEW_LINE)
			PARSE_INDEX <= 0;
		else if (PARSE_INDEX_INC_CLK_EN)
			PARSE_INDEX <= PARSE_INDEX + 1'd1;

	//wire PARSE_INDEX_INC_CLK = O102B_OUT | O109A_OUT;	// O105B
	wire PARSE_INDEX_INC_CLK_EN = O109A_OUT_RISE & ~O102B_OUT;
	/*C43 H127(PARSE_INDEX_INC_CLK, 4'b0000, 1'b1, 1'b1, 1'b1, nNEW_LINE, PARSE_INDEX[3:0], H127_CO);
	assign H125B_OUT = H127_CO | 1'b0;	// Used for test mode
	C43 I121(PARSE_INDEX_INC_CLK, 4'b0000, 1'b1, H125B_OUT, 1'b1, nNEW_LINE, PARSE_INDEX[7:4], I121_CO);
	C43 J127(PARSE_INDEX_INC_CLK, 4'b0000, 1'b1, H125B_OUT, I121_CO, nNEW_LINE, J127_Q);
	assign PARSE_INDEX[8] = J127_Q[0];*/

	wire O109A_OUT = T125A_OUT | CLK_CPU_READ_HIGH;
	wire O109A_OUT_RISE = ~O109A_OUT & (T125A_OUT_RISE | CLK_CPU_READ_HIGH_RISE);

	wire O102B_OUT = WR_ACTIVE & O98_Q;
	
	
	// Y parse matching
	// L200 O200
	assign PARSE_LOOKAHEAD = 8'd2 + {RASTERC[7:1], K260B_OUT};
	// M190 N190
	assign PARSE_ADD_Y = PARSE_LOOKAHEAD + PARSE_Y[7:0];
	wire N186_OUT = ~^{PARSE_ADD_Y[8], PARSE_Y[8]};
	// K195 M151
	assign PARSE_ADD_SIZE = {N186_OUT, ~PARSE_ADD_Y[7:4]} + PARSE_SIZE[4:0];
	wire PARSE_MATCH = PARSE_ADD_SIZE[5];
	
	
	// OK
	// Pipeline for x position and h-shrink
	// Implemented as 14-bit 3-stage shift register
	//always @(posedge N98_QD)
	//	SR_SPR_PARAMS <= {SR_SPR_PARAMS[27:0], {SPR_CHAIN, O141_Q, F[15:7]}};
	always @(posedge CLK)
		if (N98_QD_RISE) SR_SPR_PARAMS <= {SR_SPR_PARAMS[27:0], {SPR_CHAIN, XSHRINK, F[15:7]}};

	assign O159_QB = SR_SPR_PARAMS[13];
	assign HSHRINK = SR_SPR_PARAMS[40:37];
	assign PIPE_C = SR_SPR_PARAMS[41:28];
	/*
	// O159 P131 O87 N131
	FDS16bit O159(N98_QD, {2'b00, SPR_CHAIN, O141_Q, F[15:7]}, PIPE_A);
	assign O159_QB = PIPE_A[13];
	// P165 P121 P87 N121
	FDS16bit P165(N98_QD, PIPE_A, PIPE_B);
	// P155 P141 P104 N141
	FDS16bit P155(N98_QD, PIPE_B, PIPE_C);
	assign HSHRINK = PIPE_C[12:9];
	*/

endmodule
