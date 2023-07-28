//============================================================================
//  SNK NeoGeo for MiSTer
//
//  Copyright (C) 2018 Sean 'Furrtek' Gonsalves
//  Rewrite to fully synchronous logic by (C) 2023 Gyorgy Szombathelyi
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

/* verilator lint_off PINMISSING */

module lspc_timer_sync(
	input CLK,
	input LSPC_6M,
	input LSPC_EN_6M_N,
	input LSPC_EN_6M_P,
	input nRESETP,
	input [15:0] M68K_DATA,
	input WR_TIMER_HIGH,
	input WR_TIMER_LOW,
	input VMODE,
	input [2:0] TIMER_MODE,
	input TIMER_STOP,
	input [8:0] RASTERC,
	input TIMER_IRQ_EN,
	input R74_nQ_EN,
	input BNKB,
	output D46A_OUT
);
	
	wire [15:0] REG_TIMERHIGH;
	wire [15:0] REG_TIMERLOW;

	
	reg nTIMER_EN;
	// Lower 16 bits
	// K104 K68 K87 K121
	//FDS16bit K104(WR_TIMER_LOW, M68K_DATA, REG_TIMERLOW);
	register #(16) K104(CLK, 1'b0, 1'b0, WR_TIMER_LOW, M68K_DATA, REG_TIMERLOW);

	/*
	wire nTIMER_EN, L127_CO, M125_CO;
	C43 L127(~LSPC_6M, ~REG_TIMERLOW[3:0], nRELOAD, nTIMER_EN, nTIMER_EN, nRESETP, , L127_CO);
	C43 M125(~LSPC_6M, ~REG_TIMERLOW[7:4], nRELOAD, L127_CO, nTIMER_EN, nRESETP, , M125_CO);
	
	wire M52_OUT = M125_CO ^ 1'b0;	// Used for test mode
	
	wire L107A_OUT = L127_CO;
	wire M54_CO, L81_CO;
	C43 M54(~LSPC_6M, ~REG_TIMERLOW[11:8], nRELOAD, L107A_OUT, M52_OUT, nRESETP, , M54_CO);
	C43 L81(~LSPC_6M, ~REG_TIMERLOW[15:12], nRELOAD, L107A_OUT, M54_CO, nRESETP, , L81_CO);
	
	*/
	reg [15:0] TIMER_LOW;
	always @(posedge CLK)
		if (LSPC_EN_6M_N) begin
			if (!nRESETP)
				TIMER_LOW <= 0;
			else if (!nRELOAD)
				TIMER_LOW <= ~REG_TIMERLOW;
			else if (nTIMER_EN)
				TIMER_LOW <= TIMER_LOW + 1'd1;
		end
	//wire L81_CO = nTIMER_EN & &TIMER_LOW;
	wire L127_CO = nTIMER_EN & &TIMER_LOW[3:0];
	
	// Higher 16 bits
	// K31 G50 K48 K58
	//FDS16bit K31(WR_TIMER_HIGH, M68K_DATA, REG_TIMERHIGH);
	register #(16) K31(CLK, 1'b0, 1'b0, WR_TIMER_HIGH, M68K_DATA, REG_TIMERHIGH);
	/*
	wire L106A_OUT = L127_CO;
	wire L76_OUT = L81_CO ^ 1'b0;	// Used for test mode
	
	wire N50_CO, M18_CO;
	C43 N50(~LSPC_6M, ~REG_TIMERHIGH[3:0], nRELOAD, L106A_OUT, L76_OUT, nRESETP, , N50_CO);
	C43 M18(~LSPC_6M, ~REG_TIMERHIGH[7:4], nRELOAD, L106A_OUT, N50_CO, nRESETP, , M18_CO);
	
	wire K29_OUT = M18_CO ^ 1'b0;	// Used for test mode
	
	wire L51_CO, TIMER_CO;
	C43 L51(~LSPC_6M, ~REG_TIMERHIGH[11:8], nRELOAD, L106A_OUT, K29_OUT, nRESETP, , L51_CO);
	C43 L16(~LSPC_6M, ~REG_TIMERHIGH[15:12], nRELOAD, L106A_OUT, L51_CO, nRESETP, , TIMER_CO);
	*/
	reg [15:0] TIMER_HIGH;
	always @(posedge CLK)
		if (LSPC_EN_6M_N) begin
			if (!nRESETP)
				TIMER_HIGH <= 0;
			else if (!nRELOAD)
				TIMER_HIGH <= ~REG_TIMERHIGH;
			else if (nTIMER_EN & &TIMER_LOW)
				TIMER_HIGH <= TIMER_HIGH + 1'd1;
		end
	wire TIMER_CO = nTIMER_EN & &TIMER_LOW & &TIMER_HIGH;

	// Mode 0 reload pulse gen
	wire E10_Q;
	reg E20_Q, E20_nQ, E32_nQ;
	//FDPCell E10(WR_TIMER_LOW, 1'b0, E14A_OUT, 1'b1, E10_Q);
	register E10(CLK, !E14A_OUT, 1'b0, WR_TIMER_LOW, 1'b0, E10_Q);
	//FDPCell E20(~LSPC_6M, E10_Q, 1'b1, nRESETP, E20_Q, E20_nQ);
	//FDPCell E32(~LSPC_6M, E20_Q, 1'b1, nRESETP, , E32_nQ);
	always @(posedge CLK) 
		if (LSPC_EN_6M_N) begin
			{E20_Q, E20_nQ} <= {E10_Q, ~E10_Q};
			E32_nQ <= ~E20_Q;
		end
	wire E14A_OUT = ~&{E20_nQ, E32_nQ};
	wire RELOAD_MODE0 = ~|{E32_nQ, ~TIMER_MODE[0], E20_Q};

	// Mode 1 reload pulse gen
	reg K18_Q, E16_Q, E36_Q, E46_nQ;
	//FDPCell K18(R74_nQ, BNKB, nRESETP, 1'b1, K18_Q);
	always @(posedge CLK, negedge nRESETP)
		if (!nRESETP)
			K18_Q <= 0;
		else if (R74_nQ_EN)
			K18_Q <= BNKB;
	//FDPCell E16(LSPC_6M, K18_Q, nRESETP, 1'b1, E16_Q);
	//FDPCell E36(~LSPC_6M, E16_Q, nRESETP, 1'b1, E36_Q);
	//FDM E46(~LSPC_6M, E36_Q, , E46_nQ);
	always @(posedge CLK, negedge nRESETP)
		if (!nRESETP) begin
			//K18_Q <= 0;
			E16_Q <= 0;
			E36_Q <= 0;
		end else if (LSPC_EN_6M_P)
			E16_Q <= K18_Q;
		else if (LSPC_EN_6M_N) begin
			E36_Q <= E16_Q;
			E46_nQ <= ~E36_Q;
		end

	wire RELOAD_MODE1 = ~|{~TIMER_MODE[1], E46_nQ, E36_Q};

	// Mode 2 reload pulse gen and IRQ
	wire K22A_OUT = L127_CO & TIMER_CO;
	reg E43_nQ;
	//FDM E43(~LSPC_6M, K22A_OUT, , E43_nQ);
	always @(posedge CLK) if (LSPC_EN_6M_N) E43_nQ <= ~K22A_OUT;

	wire RELOAD_MODE2 = TIMER_MODE[2] & K22A_OUT;
	assign D46A_OUT = ~|{~TIMER_IRQ_EN, E43_nQ};
	
	wire nRELOAD = ~|{RELOAD_MODE0, RELOAD_MODE1, RELOAD_MODE2};
	
	// Stop option
	wire J257A_OUT = ~|{RASTERC[5:4]};
	wire I234_OUT = |{RASTERC[8], ~VMODE, ~TIMER_STOP};
	wire J238B_OUT = ~|{J257A_OUT, I234_OUT};
	//FDM J69(LSPC_6M, J238B_OUT, , nTIMER_EN);
	always @(posedge CLK) if (LSPC_EN_6M_P) nTIMER_EN <= ~J238B_OUT;

endmodule
