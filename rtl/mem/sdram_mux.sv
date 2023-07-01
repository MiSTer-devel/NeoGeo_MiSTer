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
	input             CLK,

	input             nRESET,
	input             nSYSTEM_G,
	input             SYSTEM_CDx,

	input      [20:1] M68K_ADDR,
	input      [15:0] M68K_DATA,
	input             nAS,
	input             nLDS,
	input             nUDS,
	input             DATA_TYPE,
	input             nROMOE,
	input             nPORTOE,
	input             nSROMOE,
	input      [26:0] P2ROM_ADDR,
	output reg [15:0] PROM_DATA,
	output reg        PROM_DATA_READY,

	input             PCK2,
	input      [15:0] S_LATCH,
	input       [1:0] FIX_BANK,
	input             FIX_EN,
	output reg [15:0] SROM_DATA,	// 4 pixels

	input             PCK1,
	input      [26:0] CROM_ADDR,
	input             SPR_EN,
	output reg [63:0] CR_DOUBLE,	// 16 pixels

	output reg        SDRAM_WR,
	output reg        SDRAM_RD,
	output reg        SDRAM_BURST,
	output reg [26:1] SDRAM_ADDR,
	input      [63:0] SDRAM_DOUT,
	output     [15:0] SDRAM_DIN,
	input             SDRAM_READY,
	output      [1:0] SDRAM_BS,

	input             DL_EN,
	input      [15:0] DL_DATA,
	input      [26:0] DL_ADDR,
	input             DL_WR,

	input             DMA_RUNNING,
	input             DMA_WR_OUT,
	input      [23:0] DMA_ADDR_IN,
	input      [23:0] DMA_ADDR_OUT,
	input      [15:0] DMA_DATA_OUT,
	output reg        DMA_SDRAM_BUSY,
	input       [2:0] CD_TR_AREA,
	input             CD_EXT_WR,
	input             CD_EXT_RD,
	input       [1:0] CD_BANK_SPR,
	input             CD_USE_SPR,
	input             CD_TR_RD_SPR,
	input             CD_USE_FIX,
	input             CD_TR_RD_FIX,
	input             CD_TR_WR_FIX,
	input             CD_WR_SDRAM_SIG
);

	localparam P2ROM_OFFSET = 27'h0300000;

	reg [24:0] CD_REMAP_TR_ADDR;
	reg [15:0] wr_data;
	reg        SDRAM_WR_BYTE_MODE;
	reg [26:1] dl_addr;
	reg [15:0] dl_data;

	assign SDRAM_BS = (DL_EN | ~SDRAM_WR_BYTE_MODE) ? 2'b11 : {~CD_REMAP_TR_ADDR[0],CD_REMAP_TR_ADDR[0]};
	assign SDRAM_DIN = DL_EN ? dl_data : wr_data;

	reg M68K_RD_RUN, SFIX_RD_RUN, CROM_RD_RUN, CD_TR_RUN;

	// SDRAM address mux
	always_comb begin 
		casez ({DL_EN, CD_TR_RUN, SFIX_RD_RUN, M68K_RD_RUN, ~nROMOE, ~nPORTOE})
			// HPS loading pass-through
			6'b1zzzzz: SDRAM_ADDR = dl_addr;

			// CD transfer
			6'b01zzzz: SDRAM_ADDR = CD_REMAP_TR_ADDR[24:1];

			// SFIX ROM (CD)		$0080000~$009FFFF
			// S1 ROM (cart)		$0080000~$00FFFFF
			// SFIX ROM (cart)	$0020000~$003FFFF
			6'b001zzz: SDRAM_ADDR = SYSTEM_CDx ? {8'b0_0000_100,         S_LATCH[15:4], S_LATCH[2:0], ~S_LATCH[3]}:
												nSYSTEM_G ? {6'b0_0000_1, FIX_BANK, S_LATCH[15:4], S_LATCH[2:0], ~S_LATCH[3]}:
												            {8'b0_0000_001,         S_LATCH[15:4], S_LATCH[2:0], ~S_LATCH[3]};

			// P1 ROM $0200000~$02FFFFF
			6'b00011z: SDRAM_ADDR =                {5'b0_0010,      M68K_ADDR[19:1]};

			// P2 ROM (cart) $0300000~... bankswitched
			6'b000101: SDRAM_ADDR =               P2ROM_OFFSET[26:1] + P2ROM_ADDR[26:1];

			// System ROM (CD)	$0000000~$007FFFF
			// System ROM (cart)	$0000000~$001FFFF
			6'b000100: SDRAM_ADDR = SYSTEM_CDx  ? {6'b0_0000_0,    M68K_ADDR[18:1]} :
															   {8'b0_0000_000,  M68K_ADDR[16:1]} ;

			// C ROMs Bytes $0800000~$7FFFFFF
			default:    SDRAM_ADDR =               CROM_ADDR[26:1];
		endcase
	end

	reg SDRAM_M68K_SIG_SR;
	reg SDRAM_CROM_SIG_SR;
	reg SDRAM_SROM_SIG_SR;

	wire SDRAM_M68K_SIG = ~&{nSROMOE, nROMOE, nPORTOE};

	wire REQ_M68K_RD = (~SDRAM_M68K_SIG_SR & SDRAM_M68K_SIG);
	wire REQ_CROM_RD = (SDRAM_CROM_SIG_SR & ~PCK1) & SPR_EN & ~CD_USE_SPR;
	wire REQ_SROM_RD = (SDRAM_SROM_SIG_SR & ~PCK2) & FIX_EN & ~CD_USE_FIX;

	wire CD_RD_SDRAM_SIG = CD_EXT_RD | CD_TR_RD_FIX | CD_TR_RD_SPR;
	wire CD_LDS_ONLY_WR = CD_TR_WR_FIX;

	always @(posedge CLK) begin
		reg M68K_RD_REQ, SROM_RD_REQ, CROM_RD_REQ, CD_WR_REQ;
		reg nAS_PREV;
		reg CD_WR_SDRAM_SIG_PREV, CD_RD_SDRAM_SIG_PREV;
		reg old_ready;

		if(DL_WR & DL_EN) begin
			dl_addr <= DL_ADDR[26:1];
			dl_data <= DL_DATA;
			SDRAM_WR <= 1;
		end
		
		old_ready <= SDRAM_READY;
		if(old_ready & ~SDRAM_READY) begin
			SDRAM_WR <= 0;
			SDRAM_RD <= 0;
		end

		nAS_PREV <= nAS;

		CD_RD_SDRAM_SIG_PREV <= CD_RD_SDRAM_SIG;
		CD_WR_SDRAM_SIG_PREV <= CD_WR_SDRAM_SIG;

		SDRAM_M68K_SIG_SR <= SDRAM_M68K_SIG;
		SDRAM_CROM_SIG_SR <= PCK1;
		SDRAM_SROM_SIG_SR <= PCK2;

		if (!nRESET) begin
			CROM_RD_REQ <= 0;
			SROM_RD_REQ <= 0;
			M68K_RD_REQ <= 0;
			CD_WR_REQ   <= 0;

			CROM_RD_RUN <= 0;
			SFIX_RD_RUN <= 0;
			M68K_RD_RUN <= 0;
			CD_TR_RUN   <= 0;

			DMA_SDRAM_BUSY <= 0;
			
			if(~DL_EN) begin
				SDRAM_WR <= 0;
				SDRAM_RD <= 0;
			end
		end
		else begin
			if (~nAS_PREV & nAS) PROM_DATA_READY <= 0;
			if (~DMA_RUNNING) DMA_SDRAM_BUSY <= 0;

			// Detect 68k or DMA requests for CD specific reads/writes
			if ((~CD_RD_SDRAM_SIG_PREV & CD_RD_SDRAM_SIG) | (~CD_WR_SDRAM_SIG_PREV & CD_WR_SDRAM_SIG)) begin
				// Convert and latch address
				casez({CD_EXT_RD, CD_EXT_WR, CD_TR_AREA})
					// Read P1 (CD DMA) or Extended RAM (CD DMA+68K) $0100000~$01FFFFF
					5'b1_?_???: CD_REMAP_TR_ADDR <= DMA_RUNNING ? {3'b0_00, ~DMA_ADDR_IN[20], DMA_ADDR_IN[20:1], 1'b0}   : {3'b0_00, ~M68K_ADDR[20], M68K_ADDR[20:1], ~nLDS};

					// Write P1 or Extended RAM
					5'b0_1_???: CD_REMAP_TR_ADDR <= DMA_RUNNING ? {3'b0_00, ~DMA_ADDR_OUT[20], DMA_ADDR_OUT[20:1], 1'b0} : {3'b0_00, ~M68K_ADDR[20], M68K_ADDR[20:1], ~nLDS};

					// Sprites SDRAM
					5'b0_0_000: CD_REMAP_TR_ADDR <= DMA_RUNNING ? {3'b0_10, CD_BANK_SPR, DMA_ADDR_OUT[19:7], DMA_ADDR_OUT[5:2], ~DMA_ADDR_OUT[6], ~DMA_ADDR_OUT[1], 1'b0} : {3'b0_10, CD_BANK_SPR, M68K_ADDR[19:7], M68K_ADDR[5:2], ~M68K_ADDR[6], ~M68K_ADDR[1], ~nLDS};

					// FIX SDRAM
					5'b0_0_101: CD_REMAP_TR_ADDR <= DMA_RUNNING ? {8'b0_0000_100, DMA_ADDR_OUT[17:6], DMA_ADDR_OUT[3:1], ~DMA_ADDR_OUT[5], ~DMA_ADDR_OUT[4]} : {8'b0_0000_100, M68K_ADDR[17:6], M68K_ADDR[3:1], ~M68K_ADDR[5], ~M68K_ADDR[4]};

					default:  CD_REMAP_TR_ADDR <= 25'h0AAAAAA;		// DEBUG
				endcase

				if (CD_RD_SDRAM_SIG) begin // read
					M68K_RD_REQ <= 1;
				end else begin
					// DMA writes are always done in words. FIX layer is on a 8bit bus so should only write the low byte.
					SDRAM_WR_BYTE_MODE <= (CD_LDS_ONLY_WR | ((CD_EXT_WR | (CD_TR_AREA == 3'd0)) & (nLDS ^ nUDS)));	// Fix or extended RAM data

					wr_data <= DMA_RUNNING ? (CD_LDS_ONLY_WR ? {DMA_DATA_OUT[7:0],DMA_DATA_OUT[7:0]} :  DMA_DATA_OUT)
										   : (CD_LDS_ONLY_WR ? {M68K_DATA[7:0],M68K_DATA[7:0]} : M68K_DATA);

					// In DMA, start if: nothing is running, no LSPC read (priority case C)
					// Out of DMA, start if: nothing is running (priority case B)
					// TO TEST
					CD_WR_REQ <= 1;
				end
			end

			// Detect 68k read requests
			// Detect rising edge of SDRAM_M68K_SIG
			if (REQ_M68K_RD) M68K_RD_REQ <= 1;

			// Detect sprite data read requests
			// Detect rising edge of PCK1B
			if (REQ_CROM_RD) CROM_RD_REQ <= 1;

			// Detect fix data read requests
			// Detect rising edge of PCK2B
			// See dev_notes.txt about why there's only one read for FIX graphics
			// regardless of the S2H1 signal
			if (REQ_SROM_RD) SROM_RD_REQ <= 1;

			if (SDRAM_READY & ~SDRAM_RD & ~SDRAM_WR) begin

				// Terminate running access, if needed
				// Having two non-nested IF statements with the & in the condition
				// prevents synthesis from chaining too many muxes and causing
				// timing analysis to fail
				if (CD_TR_RUN)	begin
					CD_TR_RUN      <= 0;
					DMA_SDRAM_BUSY <= 0;
				end
				if (SFIX_RD_RUN) begin
					SROM_DATA      <= SDRAM_DOUT[15:0];
					SFIX_RD_RUN    <= 0;
				end
				if (M68K_RD_RUN) begin
					PROM_DATA      <= SDRAM_DOUT[15:0];
					PROM_DATA_READY<= 1;
					M68K_RD_RUN    <= 0;
					DMA_SDRAM_BUSY <= 0;
				end
				if (CROM_RD_RUN) begin
					CR_DOUBLE      <= SDRAM_DOUT;
					CROM_RD_RUN    <= 0;
				end

				// Start requested access, if needed
				if (M68K_RD_REQ | REQ_M68K_RD) begin
					M68K_RD_REQ    <= 0;
					M68K_RD_RUN    <= 1;
					CD_TR_RUN      <= CD_RD_SDRAM_SIG;
					SDRAM_RD       <= 1;
					SDRAM_BURST    <= 0;
					DMA_SDRAM_BUSY <= DMA_RUNNING;
				end
				else if (CROM_RD_REQ | REQ_CROM_RD) begin
					CROM_RD_REQ    <= 0;
					CROM_RD_RUN    <= 1;
					SDRAM_RD       <= 1;
					SDRAM_BURST    <= 1;
				end
				else if (SROM_RD_REQ | REQ_SROM_RD) begin
					SROM_RD_REQ    <= 0;
					SFIX_RD_RUN    <= 1;
					SDRAM_RD       <= 1;
					SDRAM_BURST    <= 0;
				end
				else if (CD_WR_REQ) begin
					CD_WR_REQ      <= 0;
					CD_TR_RUN      <= 1;
					SDRAM_WR       <= 1;
					DMA_SDRAM_BUSY <= DMA_RUNNING;
				end
			end
		end
	end
endmodule
