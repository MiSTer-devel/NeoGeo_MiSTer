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

// SDRAM mux/demux logic

module sdram_mux(
	input nRESET,
	input clk_sys,
	
	input nAS,
	input nLDS,
	input nUDS,
	
	input [15:0] SDRAM_DQ,	// TESTING
	
	input [2:0] CD_TR_AREA,
	input CD_EXT_WR,
	
	input DMA_RUNNING,
	input DMA_WR_OUT,
	input [23:0] DMA_ADDR_IN,
	input [23:0] DMA_ADDR_OUT,
	input [15:0] DMA_DATA_OUT,
	output reg DMA_SDRAM_BUSY,
	
	input [20:1] M68K_ADDR,
	input [15:0] M68K_DATA,
	
	input PCK1, PCK2,
	input CD_WR_SDRAM_SIG,
	
	output reg SDRAM_WR_PULSE,
	output reg SDRAM_RD_PULSE,
	output reg SDRAM_RD_TYPE,
	
	output reg [15:0] PROM_DATA,
	output reg [63:0] CR_DOUBLE,	// 16 pixels
	output reg [15:0] SROM_DATA,	// 4 pixels
	output reg PROM_DATA_READY,
	input [1:0] FIX_BANK,
	
	input SPR_EN, FIX_EN,
	
	output reg [26:0] sdram_addr,
	input [63:0] sdram_dout,
	output [15:0] sdram_din,
	input sdram_ready, //ready_fourth,
	
	input ioctl_download,
	input [26:0] ioctl_addr_offset,
	
	input [26:0] P2ROM_ADDR,

	input [1:0] CD_BANK_SPR,
	input [26:0] CROM_ADDR,
	input [15:0] S_LATCH,
	input nROMOE, CD_EXT_RD, nPORTOE, nSROMOE,
	
	input nSYSTEM_G, SYSTEM_CDx,
	
	output [1:0] wtbt,
	input [15:0] ioctl_dout
);

	reg M68K_RD_REQ, SROM_RD_REQ, CROM_RD_REQ, CD_WR_REQ;
	reg M68K_RD_RUN, SROM_RD_RUN, CROM_RD_RUN, CD_WR_RUN;

	reg nDS_PREV, nAS_PREV, DMA_WR_OUT_PREV;
	reg [1:0] SDRAM_READY_SR;
	//reg [1:0] SDRAM_READY_FOURTH_SR;
	reg [1:0] SDRAM_M68K_SIG_SR;
	reg [1:0] SDRAM_CROM_SIG_SR;
	reg [1:0] SDRAM_SROM_SIG_SR;

	reg [24:0] CD_REMAP_TR_ADDR;

	reg SDRAM_WR_BYTE_MODE;

	assign wtbt = (ioctl_download | ~CD_WR_RUN) ? 2'b11 : SDRAM_WR_BYTE_MODE ? 2'b00 : 2'b11;

	assign sdram_din = ioctl_download ? ioctl_dout :
								CD_WR_RUN ? DMA_RUNNING ? DMA_DATA_OUT : M68K_DATA : 16'h0000;

	// Only allow DMA to read from $000000~$1FFFFF
	wire SDRAM_M68K_SIG = DMA_RUNNING ? CD_EXT_RD : ~&{nSROMOE, nROMOE, nPORTOE} | CD_EXT_RD;

	// SDRAM address mux
	// sdram_addr LSB is = 0 in word mode
	always_comb begin 
		casez ({ioctl_download, CD_WR_RUN, CD_EXT_RD & M68K_RD_RUN, ~nROMOE & M68K_RD_RUN, ~nPORTOE & M68K_RD_RUN, ~nSROMOE & M68K_RD_RUN, SROM_RD_RUN}) //, CROM_RD_RUN})
			// HPS loading pass-through
			7'b1zzzzzz: sdram_addr = ioctl_addr_offset;

			// CD transfer
			7'b01zzzzz: sdram_addr = CD_REMAP_TR_ADDR;

			// Work RAM (cart) $0100000~$010FFFF, or Extended RAM (CD) $0100000~$01FFFFF
			7'b001zzzz: sdram_addr = ~SYSTEM_CDx  ? {9'b0_0001_0000, M68K_ADDR[15:1], 1'b0} :
		                             DMA_RUNNING ? {5'b0_0001,      DMA_ADDR_IN[19:0]}     :
											                {5'b0_0001,      M68K_ADDR[19:1], 1'b0} ;

			// P1 ROM $0200000~$02FFFFF
			7'b0001zzz: sdram_addr =                {5'b0_0010,      M68K_ADDR[19:1], 1'b0};

			// P2 ROM (cart) $0300000~... bankswitched
			7'b00001zz: sdram_addr =                27'h0300000 + P2ROM_ADDR;

			// System ROM (CD)	$0000000~$007FFFF
			// System ROM (cart)	$0000000~$001FFFF
			7'b000001z: sdram_addr = SYSTEM_CDx   ? {6'b0_0000_0,    M68K_ADDR[18:1], 1'b0} :
															    {8'b0_0000_000,  M68K_ADDR[16:1], 1'b0} ;

			// SFIX ROM (CD)		$0080000~$009FFFF
			// S1 ROM (cart)		$0080000~$00FFFFF
			// SFIX ROM (cart)	$0020000~$003FFFF
			7'b0000001: sdram_addr = SYSTEM_CDx   ? {8'b0_0000_100,  S_LATCH[15:4], S_LATCH[2:0], ~S_LATCH[3], 1'b0} :
												nSYSTEM_G  ? {6'b0_0000_1,    FIX_BANK, S_LATCH[15:4], S_LATCH[2:0], ~S_LATCH[3], 1'b0} :
												             {8'b0_0000_001,  S_LATCH[15:4], S_LATCH[2:0], ~S_LATCH[3], 1'b0};

			// Default: C ROMs Bytes $0800000~$7FFFFFF
			7'b0000000: sdram_addr =                CROM_ADDR;
		endcase
	end

	always @(posedge clk_sys)
	begin
		if (!nRESET)
		begin
			CROM_RD_REQ <= 0;
			SROM_RD_REQ <= 0;
			M68K_RD_REQ <= 0;
			CD_WR_REQ <= 0;
			
			CROM_RD_RUN <= 0;
			SROM_RD_RUN <= 0;
			M68K_RD_RUN <= 0;
			CD_WR_RUN <= 0;
			
			SDRAM_WR_BYTE_MODE <= 0;
			DMA_SDRAM_BUSY <= 0;
			
			nDS_PREV <= 1;
			DMA_WR_OUT_PREV <= 0;
		end
		else
		begin
			nAS_PREV <= nAS;
			
			if ({nAS_PREV, nAS} == 2'b01)
				PROM_DATA_READY <= 0;
			
			if (!DMA_RUNNING)
				DMA_SDRAM_BUSY <= 0;
			
			// Detect 68k or DMA write requests
			// Detect falling edge of nLDS or nUDS, or rising edge of DMA_WR_OUT while CD_WR_SDRAM_SIG is high
			nDS_PREV <= nLDS & nUDS;
			DMA_WR_OUT_PREV <= DMA_WR_OUT;
			if (((nDS_PREV & ~(nLDS & nUDS)) | (~DMA_WR_OUT_PREV & DMA_WR_OUT)) & CD_WR_SDRAM_SIG)
			begin
				if (DMA_RUNNING)
					DMA_SDRAM_BUSY <= 1;
				
				// Convert and latch address
				casez({CD_EXT_WR, CD_TR_AREA})
					4'b1_???: CD_REMAP_TR_ADDR <= DMA_RUNNING ? {1'b0, 4'h3 + DMA_ADDR_OUT[20], DMA_ADDR_OUT[19:1], 1'b0} : {1'b0, 4'h3 + M68K_ADDR[20], M68K_ADDR[19:1], ~nLDS};	// EXT zone SDRAM
					4'b0_000: CD_REMAP_TR_ADDR <= DMA_RUNNING ? {3'b0_10, CD_BANK_SPR, DMA_ADDR_OUT[19:7], DMA_ADDR_OUT[5:2], ~DMA_ADDR_OUT[6], ~DMA_ADDR_OUT[1], 1'b0} : {3'b0_10, CD_BANK_SPR, M68K_ADDR[19:7], M68K_ADDR[5:2], ~M68K_ADDR[6], ~M68K_ADDR[1], 1'b0};	// Sprites SDRAM
					//4'b0_001: CD_REMAP_TR_ADDR <= {4'b0_000, CD_BANK_PCM, CD_TR_WR_ADDR, 1'b0};		// ADPCM DDRAM
					4'b0_101: CD_REMAP_TR_ADDR <= DMA_RUNNING ? {8'b0_0010_100, DMA_ADDR_OUT[17:6], DMA_ADDR_OUT[3:1], ~DMA_ADDR_OUT[5], ~DMA_ADDR_OUT[4]} : {8'b0_0010_100, M68K_ADDR[17:6], M68K_ADDR[3:1], ~M68K_ADDR[5], ~M68K_ADDR[4]};	// Fix SDRAM
					//4'b0_100: CD_REMAP_TR_ADDR <= {8'b0_0000_000, CD_TR_WR_ADDR[16:1], 1'b0};		// Z80 BRAM
					default: CD_REMAP_TR_ADDR <= 25'h0AAAAAA;		// DEBUG
				endcase
				
				SDRAM_WR_BYTE_MODE <= DMA_RUNNING ? 1'b0 :	// DMA writes are always done in words
											((CD_TR_AREA == 3'd5) & ~CD_EXT_WR) | (CD_EXT_WR & (nLDS ^ nUDS));	// Fix or extended RAM data
				
				// In DMA, start if: nothing is running, no LSPC read (priority case C)
				// Out of DMA, start if: nothing is running (priority case B)
				// TO TEST
				if (~|{M68K_RD_RUN, CROM_RD_RUN, SROM_RD_RUN, M68K_RD_REQ, CROM_RD_REQ, SROM_RD_REQ} & sdram_ready)
				begin
					if (DMA_RUNNING)
					begin
						if ((SDRAM_CROM_SIG_SR != 2'b01) & (SDRAM_SROM_SIG_SR != 2'b01))
						begin
							// Start write cycle right now
							CD_WR_RUN <= 1;
							SDRAM_WR_PULSE <= 1;
						end
						else
							CD_WR_REQ <= 1;	// Set request flag for later
					end
					else
					begin
						// Start write cycle right now
						CD_WR_RUN <= 1;
						SDRAM_WR_PULSE <= 1;
					end
				end
				else
					CD_WR_REQ <= 1;	// Set request flag for later
			end
			
			// Detect 68k read requests
			// Detect rising edge of SDRAM_M68K_SIG
			// TODO: Does this really need 2 FFs ?
			SDRAM_M68K_SIG_SR <= {SDRAM_M68K_SIG_SR[0], SDRAM_M68K_SIG};
			if ((SDRAM_M68K_SIG_SR == 2'b01))	// & M68K_CACHE_MISS)
			begin
				// In DMA, start if: nothing is running, no LSPC read (priority case C)
				// Out of DMA, start if: nothing is running (priority case A)
				// TO TEST
				if (~|{CD_WR_RUN, CROM_RD_RUN, SROM_RD_RUN, CD_WR_RUN, CROM_RD_REQ, SROM_RD_REQ} & sdram_ready)
				begin
					if (DMA_RUNNING)
					begin
						DMA_SDRAM_BUSY <= 1;
						
						if ((SDRAM_CROM_SIG_SR != 2'b01) & (SDRAM_SROM_SIG_SR != 2'b01))
						begin
							// Start read cycle right now
							M68K_RD_RUN <= 1;
							SDRAM_RD_PULSE <= 1;
							SDRAM_RD_TYPE <= 0;	// Single read
						end
						else
							M68K_RD_REQ <= 1;	// Set request flag for later
					end
					else
					begin
						// Start read cycle right now
						M68K_RD_RUN <= 1;
						SDRAM_RD_PULSE <= 1;
						SDRAM_RD_TYPE <= 0;	// Single read
					end
				end
				else
					M68K_RD_REQ <= 1;	// Set request flag for later
			end
			
			// Detect sprite data read requests
			// Detect rising edge of PCK1B
			// TODO: Does this really need 2 FFs ?
			SDRAM_CROM_SIG_SR <= {SDRAM_CROM_SIG_SR[0], ~PCK1};
			if ((SDRAM_CROM_SIG_SR == 2'b01) & SPR_EN)
			begin
				// In DMA, start if: nothing is running (priority case C)
				// Out of DMA, start if: nothing is running, no 68k read or write (priority cases A and B)
				// TODO
				if (~|{M68K_RD_RUN, SROM_RD_RUN, CD_WR_RUN, M68K_RD_REQ, SROM_RD_REQ} & sdram_ready)
				begin
					// Start C ROM read cycle right now
					CROM_RD_RUN <= 1;
					SDRAM_RD_PULSE <= 1;
					SDRAM_RD_TYPE <= 1;	// Burst read
				end
				else
					CROM_RD_REQ <= 1;	// Set request flag for later
			end
			
			// Detect fix data read requests
			// Detect rising edge of PCK2B
			// TODO: Does this really need 2 FFs ?
			// See dev_notes.txt about why there's only one read for FIX graphics
			// regardless of the S2H1 signal
			SDRAM_SROM_SIG_SR <= {SDRAM_SROM_SIG_SR[0], ~PCK2};
			if ((SDRAM_SROM_SIG_SR == 2'b01) & FIX_EN)
			begin
				// In DMA, start if: nothing is running (priority case C)
				// Out of DMA, start if: nothing is running, no 68k read or write (priority cases A and B)
				// TODO
				if (~|{M68K_RD_RUN, CROM_RD_RUN, CD_WR_RUN, M68K_RD_REQ, CROM_RD_REQ} & sdram_ready)
				begin
					// Start S ROM read cycle right now
					SROM_RD_RUN <= 1;
					SDRAM_RD_PULSE <= 1;
					SDRAM_RD_TYPE <= 0;	// Single read
				end
				else
					SROM_RD_REQ <= 1;	// Set request flag for later
			end
			
			if (SDRAM_WR_PULSE)
				SDRAM_WR_PULSE <= 0;
			
			if (SDRAM_RD_PULSE)
				SDRAM_RD_PULSE <= 0;
			
			if (sdram_ready & ~SDRAM_RD_PULSE & ~SDRAM_WR_PULSE)
			begin
				// Start requested access, if needed
				if (CD_WR_REQ && !CROM_RD_RUN && !M68K_RD_RUN && !SROM_RD_RUN)
				begin
					CD_WR_REQ <= 0;
					CD_WR_RUN <= 1;
					SDRAM_WR_PULSE <= 1;
				end
				else if (CROM_RD_REQ && !CD_WR_RUN && !M68K_RD_RUN && !SROM_RD_RUN)
				begin
					CROM_RD_REQ <= 0;
					if (SPR_EN)
					begin
						CROM_RD_RUN <= 1;
						SDRAM_RD_PULSE <= 1;
						SDRAM_RD_TYPE <= 1;	// Burst read
					end
				end
				else if (SROM_RD_REQ && !CD_WR_RUN && !M68K_RD_RUN && !CROM_RD_RUN)
				begin
					SROM_RD_REQ <= 0;
					if (FIX_EN)
					begin
						SROM_RD_RUN <= 1;
						SDRAM_RD_PULSE <= 1;
						SDRAM_RD_TYPE <= 0;	// Single read
					end
				end
				else if (M68K_RD_REQ && !CD_WR_RUN && !SROM_RD_RUN && !CROM_RD_RUN)
				begin
					M68K_RD_REQ <= 0;
					M68K_RD_RUN <= 1;
					SDRAM_RD_PULSE <= 1;
					SDRAM_RD_TYPE <= 0;	// Single read
				end
			end
			
			// Terminate running access, if needed
			// Having two non-nested IF statements with the & in the condition
			// prevents synthesis from chaining too many muxes and causing
			// timing analysis to fail
			SDRAM_READY_SR <= {SDRAM_READY_SR[0], sdram_ready};
			if ((SDRAM_READY_SR == 2'b01) & CD_WR_RUN)
			begin
				CD_WR_RUN <= 0;
				DMA_SDRAM_BUSY <= 0;
			end
			if ((SDRAM_READY_SR == 2'b01) & SROM_RD_RUN)
			begin
				SROM_DATA <= sdram_dout[63:48];
				SROM_RD_RUN <= 0;
			end
			// TESTING
			//if ((~SDRAM_READY_SR[0] & sdram_ready) & M68K_RD_RUN)	// 2020bb crashes with this
			if ((SDRAM_READY_SR == 2'b01) & M68K_RD_RUN)
			begin
				PROM_DATA <= sdram_dout[63:48];
				PROM_DATA_READY <= 1;
				M68K_RD_RUN <= 0;
				DMA_SDRAM_BUSY <= 0;
			end
			if ((SDRAM_READY_SR == 2'b01) & CROM_RD_RUN)
			begin
				CR_DOUBLE <= sdram_dout;
				CROM_RD_RUN <= 0;
			end
		end
	end
	
endmodule
