//============================================================================
//  SNK NeoGeo for MiSTer
//
//  Copyright (C) 2019 Sean 'Furrtek' Gonsalves
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

module cpu_68k(
	input CLK,
	input CLK_EN_68K_P, //CLK_68KCLK
	input CLK_EN_68K_N,
	input nRESET,
	input IPL2, IPL1, IPL0,
	input nDTACK,
	output [23:1] M68K_ADDR,
	input [15:0] FX68K_DATAIN,
	output [15:0] FX68K_DATAOUT,
	output nLDS, nUDS,
	output nAS,
	output M68K_RW,
	output FC2, FC1, FC0,
	output nBG,
	input nBR, nBGACK,
	input SYSTEM_CDx

);
	
wire EN_PHI1 = CLK_EN_68K_P;
wire EN_PHI2 = CLK_EN_68K_N;

reg reset;
always @(posedge CLK)
	if (EN_PHI2) reset <= ~nRESET;

fx68k FX68K(
		.clk(CLK),
		.extReset(reset),
		.pwrUp(reset),
		
		.enPhi1(EN_PHI1),
		.enPhi2(EN_PHI2),
		
		.eRWn(M68K_RW),
		.ASn(nAS),
		.UDSn(nUDS),
		.LDSn(nLDS),
		
		.BGn(nBG),
		.BRn(nBR),
		.BGACKn(nBGACK),
		
		.DTACKn(nDTACK),
		
		.VPAn(SYSTEM_CDx | nAS | ~&M68K_ADDR[23:4]), //VPA must be fired only in IACK cycle! (NeoGeo doesn't use FC)
		.BERRn(1'b1),
		
		.IPL0n(IPL0),
		.IPL1n(IPL1),
		.IPL2n(IPL2),
		
		.FC0(FC0),
		.FC1(FC1),
		.FC2(FC2),
		
		.iEdb(FX68K_DATAIN),
		.oEdb(FX68K_DATAOUT),
		.eab(M68K_ADDR)
		);
	
endmodule
