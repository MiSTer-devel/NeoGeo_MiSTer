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

module lspc2_clk_sync(
	input CLK,
	input CLK_EN_24M_P,
	input CLK_EN_24M_N,
	input nRESETP,

	output CLK_24MB,
	output LSPC_12M,
	output reg LSPC_8M,
	output LSPC_6M,
	output reg LSPC_4M,
	output LSPC_3M,
	output LSPC_1_5M,
	output Q53_CO,

	output reg LSPC_EN_12M_P,
	output reg LSPC_EN_12M_N,
	output reg LSPC_EN_6M_P,
	output reg LSPC_EN_6M_N,
	output reg LSPC_EN_3M,
	output reg LSPC_EN_1_5M_P,
	output reg LSPC_EN_1_5M_N, // Q53_CO
	output LSPC_EN_4M_P,
	output LSPC_EN_4M_N
);
reg       CLK_24M;
/* verilator lint_off UNOPTFLAT */
reg [3:0] DIV_CNT;
/* verilator lint_on UNOPTFLAT */
reg [1:0] DIV_CNT3;

always @(posedge CLK) begin
	if (CLK_EN_24M_N) begin
		CLK_24M <= 0;
		if (!nRESETP) begin
			DIV_CNT <= 4'b0010;
		end else begin
			DIV_CNT <= DIV_CNT + 1'd1;
			DIV_CNT3 <= DIV_CNT3 + 1'd1;
			if (DIV_CNT3 == 2) DIV_CNT3 <= 0;
		end
	end
	if (CLK_EN_24M_P)
		CLK_24M <= 1;

	LSPC_EN_12M_P <= CLK_EN_24M_P && ~DIV_CNT[0];
	LSPC_EN_12M_N <= CLK_EN_24M_P &&  DIV_CNT[0];
	LSPC_EN_6M_P <= CLK_EN_24M_P && (DIV_CNT[1:0] == 1);
	LSPC_EN_6M_N <= CLK_EN_24M_P && (DIV_CNT[1:0] == 3);
	LSPC_EN_3M <= CLK_EN_24M_P && (DIV_CNT[2:0] == 3);
	LSPC_EN_1_5M_P <= CLK_EN_24M_P && (DIV_CNT == 7);
	LSPC_EN_1_5M_N <= CLK_EN_24M_P && (DIV_CNT == 15);

end
assign Q53_CO = (DIV_CNT == 15); // Q53_CO

wire      CLK8_FALL = CLK_EN_24M_P & DIV_CNT3 == 2;
wire      CLK8_RISE = CLK_EN_24M_N & DIV_CNT3 == 0;
always @(posedge CLK) if (CLK8_FALL) LSPC_8M <= 0; else if (CLK8_RISE) LSPC_8M <= 1;

always @(posedge CLK) if (CLK8_FALL) LSPC_4M <= ~LSPC_4M;
assign    LSPC_EN_4M_P = ~LSPC_4M & CLK8_FALL;
assign    LSPC_EN_4M_N =  LSPC_4M & CLK8_FALL;

assign CLK_24MB = ~CLK_24M;
assign LSPC_1_5M = DIV_CNT[3];
assign LSPC_3M = DIV_CNT[2];
assign LSPC_6M = DIV_CNT[1];
assign LSPC_12M = DIV_CNT[0];

endmodule
