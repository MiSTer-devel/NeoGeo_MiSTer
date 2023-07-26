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

module cd_sys(
	input nRESET,
	//input CLK_68KCLK,
	input CLK_68KCLK_EN,
	input [23:1] M68K_ADDR,
	inout [15:0] M68K_DATA,
	input A22Z, A23Z,
	input nLDS, nUDS,
	input M68K_RW, nAS, nDTACK,
	input SYSTEM_CDx,
	input [1:0] CD_REGION,
	input [1:0] CD_SPEED,
	output reg CD_VIDEO_EN,
	output reg CD_FIX_EN,
	output reg CD_SPR_EN,
	
	output reg CD_nRESET_Z80,
	
	output CD_TR_WR_SPR,
	output CD_TR_WR_PCM,
	output CD_TR_WR_Z80,
	output CD_TR_WR_FIX,

	output CD_TR_RD_FIX,
	output CD_TR_RD_SPR,
	output CD_TR_RD_Z80,
	output CD_TR_RD_PCM,

	output reg CD_USE_FIX,
	output reg CD_USE_SPR,
	output reg CD_USE_Z80,
	output reg CD_USE_PCM,
	output reg [2:0] CD_TR_AREA,
	output reg [1:0] CD_BANK_SPR,
	output reg CD_BANK_PCM,
	output reg [15:0] CD_TR_WR_DATA,
	output reg [19:1] CD_TR_WR_ADDR,
	output reg CD_UPLOAD_EN, // The bios writes to Z80 RAM without CD_UPLOAD_EN enabled. Maybe this is only watchdog disable?

	output CD_VBLANK_IRQ_EN,

	input IACK,
	output reg CD_IRQ,
	
	input clk_sys,
	input [39:0] CDD_STATUS_IN,
	input CDD_STATUS_LATCH,
	output [39:0] CDD_COMMAND_DATA,
	output CDD_COMMAND_SEND,

	input CD_DATA_DOWNLOAD,
	input CD_DATA_WR,
	input [15:0] CD_DATA_DIN,
	input [11:1] CD_DATA_ADDR, // word address
	output CD_DATA_WR_READY, // Ready to receive sector

	input CDDA_RD,
	input CDDA_WR,
	output [15:0] CD_AUDIO_L,
	output [15:0] CD_AUDIO_R,
	output CDDA_WR_READY,

	input CD_LID,	// DEBUG
	
	// For DMA
	output reg nBR,
	input nBG,
	output reg nBGACK,
	
	output reg DMA_RUNNING,
	output reg [15:0] DMA_DATA_OUT,
	input [15:0] DMA_DATA_IN,
	output reg DMA_WR_OUT,
	output reg DMA_RD_OUT,
	output reg [23:0] DMA_ADDR_IN,	// Used for reading
	output reg [23:0] DMA_ADDR_OUT,	// Used for writing
	
	input DMA_SDRAM_BUSY
);
	parameter MCLK = 96671316;

	reg CD_nRESET_DRIVE;
	reg [15:0] REG_FF0002;
	reg [11:0] REG_FF0004;
	reg [2:0] CD_IRQ_FLAGS;
	
	reg [23:0] DMA_ADDR_A;
	reg [23:0] DMA_ADDR_B;
	reg [31:0] DMA_VALUE;
	reg [31:0] DMA_COUNT;				// TODO: This can probably be 23:0
	reg [15:0] DMA_MICROCODE [9];
	
	reg CDD_nIRQ_PREV, CDC_nIRQ_PREV;
	reg nLDS_PREV, nUDS_PREV;
	
	reg [3:0] CDD_DIN;
	wire [3:0] CDD_DOUT;

	wire HOCK, CDCK, CDD_nIRQ;

	cd_drive DRIVE(
		.clk_sys(clk_sys),
		.nRESET(nRESET & CD_nRESET_DRIVE),
		.HOCK(HOCK), .CDCK(CDCK),
		.CDD_DIN(CDD_DIN), .CDD_DOUT(CDD_DOUT),
		.CDD_nIRQ(CDD_nIRQ),
		.STATUS_IN(CDD_STATUS_IN),
		.STATUS_LATCH(CDD_STATUS_LATCH),
		.COMMAND_DATA(CDD_COMMAND_DATA),
		.COMMAND_SEND(CDD_COMMAND_SEND)
	);
	
	wire [7:0] LC8951_DOUT;
	wire CDC_nIRQ;
	wire [31:0] HEADER_DIN;

	lc8951 LC8951(
		.nRESET(nRESET),
		.clk_sys(clk_sys),
		//.CLK_12M(CLK_68KCLK),
		.CLK_68KCLK_EN(CLK_68KCLK_EN),
		.nWR(~LC8951_WR), .nRD(~LC8951_RD),
		.RS(M68K_ADDR[1]),
		.DIN(M68K_DATA[7:0]),
		.DOUT(LC8951_DOUT),
		.HEADER_DIN(HEADER_DIN),
		.SECTOR_READY(SECTOR_READY),
		.DMA_RUNNING(DMA_RUNNING),
		.CDC_nIRQ(CDC_nIRQ)
	);

	cdda CDDA(
		.CLK(clk_sys),
		.nRESET(nRESET),
		.READ(CDDA_RD),
		.WRITE(CDDA_WR),
		.DIN(CD_DATA_DIN),
		.AUDIO_L(CD_AUDIO_L),
		.AUDIO_R(CD_AUDIO_R),
		.WRITE_READY(CDDA_WR_READY)
	);

	localparam SECTOR_TIME_1X = MCLK / 75;
	localparam SECTOR_TIME_2X = MCLK / 150;
	localparam SECTOR_TIME_3X = MCLK / 225;
	localparam SECTOR_TIME_4X = MCLK / 300;

	reg [20:0] SECTOR_TIME;
	wire [20:0] SECTOR_TIME_SEL = (CD_SPEED == 2'd0) ? SECTOR_TIME_1X[20:0] :
	                              (CD_SPEED == 2'd1) ? SECTOR_TIME_2X[20:0] :
	                              (CD_SPEED == 2'd2) ? SECTOR_TIME_3X[20:0] :
	                                                   SECTOR_TIME_4X[20:0];

	reg SECTOR_READY; // For decoder interrupt
	reg SECTOR_FILLED[2];
	reg [23:0] SECTOR_TIME_CNT;

	reg FORCE_WR;
	reg [2:0] LOADING_STATE;
	reg [10:0] CACHE_RD_ADDR, CACHE_WR_ADDR;	// 0~2047
	reg CACHE_RD_BANK, CACHE_WR_BANK;
	reg CACHE_WR_EN;

	assign CD_DATA_WR_READY = ~SECTOR_FILLED[~CACHE_RD_BANK];

	reg [7:0] HEAD_0[2];
	reg [7:0] HEAD_1[2];
	reg [7:0] HEAD_2[2];
	reg [7:0] HEAD_3[2];

	assign HEADER_DIN = { HEAD_3[CACHE_RD_BANK], HEAD_2[CACHE_RD_BANK], HEAD_1[CACHE_RD_BANK], HEAD_0[CACHE_RD_BANK] };

	wire [7:0] CACHE_DIN = CACHE_WR_ADDR[0] ? CD_DATA_DIN[15:8] : CD_DATA_DIN[7:0];
	wire CACHE_WR = CACHE_WR_EN & (CD_DATA_WR_START | FORCE_WR);
	wire [7:0] CACHE_DOUT;

	dpram #(12,8) CACHE(
	.clock_a(clk_sys),
	.address_a( {CACHE_WR_BANK, CACHE_WR_ADDR} ),
	.data_a(CACHE_DIN),
	.wren_a(CACHE_WR),

	.clock_b(clk_sys),
	.address_b( {CACHE_RD_BANK, CACHE_RD_ADDR} ),
	.wren_b(0),
	.q_b(CACHE_DOUT)
);

	localparam DMA_STATE_IDLE = 4'd0, DMA_STATE_BR = 4'd1, DMA_STATE_WAIT_BG = 4'd2,
	           DMA_STATE_WAIT_AS = 4'd3, DMA_STATE_START = 4'd4,
	           DMA_STATE_CACHE_RD = 4'd5, DMA_STATE_CACHE_RD_L = 4'd6,
	           DMA_STATE_INIT_RD = 4'd7, DMA_STATE_RD = 4'd8, DMA_STATE_RD_DONE = 4'd9,
	           DMA_STATE_INIT_WR = 4'd10, DMA_STATE_WR = 4'd11, DMA_STATE_WR_DONE = 4'd12,
	           DMA_STATE_DONE = 4'd13;

	localparam DMA_COPY_CD_WORD = 3'd0, DMA_COPY_CD_BYTE = 3'd1, DMA_COPY_WORD = 3'd2,
	           DMA_COPY_BYTE = 3'd3, DMA_FILL_VALUE = 3'd4;

	reg DMA_START_PREV, DMA_START;
	reg [2:0] DMA_MODE;
	reg [3:0] DMA_STATE;
	reg [3:0] DMA_IO_CNT;
	reg [7:0] DMA_TIMER;
	reg [15:0] DMA_RD_DATA;
	reg [31:0] DMA_COUNT_RUN;
	
	reg CD_DATA_WR_PREV;
	wire CD_DATA_WR_START =  CD_DATA_WR & ~CD_DATA_WR_PREV;
	wire CD_DATA_WR_END   = ~CD_DATA_WR &  CD_DATA_WR_PREV;

	always @(posedge clk_sys)
	begin
		if (!nRESET)
		begin
			FORCE_WR <= 0;
			SECTOR_READY <= 0;
			SECTOR_FILLED[0] <= 0;
			SECTOR_FILLED[1] <= 0;
			SECTOR_TIME_CNT <= 0;
			SECTOR_TIME <= SECTOR_TIME_1X[20:0];

			LOADING_STATE <= 3'd0;	// Idle, waiting for request
			
			DMA_STATE <= 4'd0;
			nBR <= 1;
			nBGACK <= 1;
			
			DMA_RUNNING <= 0;
			DMA_TIMER <= 8'd0;
			
			CACHE_WR_EN <= 0;
			CACHE_RD_BANK <= 0;
			CACHE_WR_BANK <= 0;

			CD_DATA_WR_PREV <= 0;
		end
		else
		begin

			if (SECTOR_TIME_CNT == {1'b0, SECTOR_TIME[20:1]}) begin
				SECTOR_READY <= 0;
			end

			if (SECTOR_TIME_CNT < SECTOR_TIME) begin
				SECTOR_TIME_CNT <= SECTOR_TIME_CNT + 1'b1;
			end else begin
				if (SECTOR_FILLED[~CACHE_RD_BANK]) begin
					SECTOR_FILLED[CACHE_RD_BANK] <= 0;
					SECTOR_READY <= 1;
					CACHE_RD_BANK <= ~CACHE_RD_BANK;
					SECTOR_TIME_CNT <= 0;
					SECTOR_TIME <= SECTOR_TIME_SEL;
				end
			end

			CD_DATA_WR_PREV <= CD_DATA_WR;
			if (LOADING_STATE == 3'd0) begin
				if (CD_DATA_WR_READY) begin
					if (CD_DATA_DOWNLOAD & CD_DATA_WR_END & (CD_DATA_ADDR == 11'd6)) begin
						// Bytes 12-13 (Header 0-1)
						CACHE_WR_BANK <= ~CACHE_RD_BANK;

						HEAD_0[~CACHE_RD_BANK] <= CD_DATA_DIN[7:0];
						HEAD_1[~CACHE_RD_BANK] <= CD_DATA_DIN[15:8];

						LOADING_STATE <= 3'd1;
					end
				end
			end

			if (LOADING_STATE == 3'd1) begin
				if (CD_DATA_DOWNLOAD & CD_DATA_WR_END & (CD_DATA_ADDR == 11'd7)) begin
					// Bytes 14-15 (Header 2-3)
					HEAD_2[CACHE_WR_BANK] <= CD_DATA_DIN[7:0];
					HEAD_3[CACHE_WR_BANK] <= CD_DATA_DIN[15:8];

					CACHE_WR_ADDR <= 11'h000;
					CACHE_WR_EN <= 1;

					LOADING_STATE <= 3'd2;
				end
			end

			if (LOADING_STATE == 3'd2) begin
				if (CD_DATA_WR_START) begin
					// First byte of pair was written by CD_DATA_WR
					CACHE_WR_ADDR <= CACHE_WR_ADDR + 1'b1;
					LOADING_STATE <= 3'd3;
					FORCE_WR <= 1;
				end

				if (~CD_DATA_DOWNLOAD) begin // Incomplete data, should not happen.
					LOADING_STATE <= 3'd4;
				end
			end

			if (LOADING_STATE == 3'd3) begin
				// Second byte of pair was written by FORCE_WR
				FORCE_WR <= 0;
				CACHE_WR_ADDR <= CACHE_WR_ADDR + 1'b1;
				if (CACHE_WR_ADDR == 11'd2047) begin
					LOADING_STATE <= 3'd4;
				end else begin
					LOADING_STATE <= 3'd2;
				end
			end

			if (LOADING_STATE == 3'd4) begin
				// Sector load done
				CACHE_WR_EN <= 0;
				SECTOR_FILLED[CACHE_WR_BANK] <= 1;
				LOADING_STATE <= 3'd0;
			end

			DMA_START_PREV <= DMA_START;

			// Rising edge of DMA_START
			if (~DMA_START_PREV & DMA_START)
			begin
				DMA_STATE <= 4'd1;
				DMA_RUNNING <= 1;
				DMA_IO_CNT <= 4'd0;

				DMA_COUNT_RUN <= DMA_COUNT;

				case (DMA_MODE)

					DMA_COPY_CD_WORD, DMA_COPY_CD_BYTE:
					begin
						// Init byte copy LC8951 cache -> DMA_ADDR_A
						DMA_ADDR_OUT <= DMA_ADDR_A;
						CACHE_RD_ADDR <= 11'h000;
					end

					DMA_COPY_WORD, DMA_COPY_BYTE:
					begin
						// Init copy DMA_ADDR_A -> DMA_ADDR_B
						DMA_ADDR_IN <= DMA_ADDR_A;
						DMA_ADDR_OUT <= DMA_ADDR_B;
					end

					DMA_FILL_VALUE:
					begin
						// Init word fill from DMA_ADDR_A
						DMA_ADDR_OUT <= DMA_ADDR_A;
						DMA_DATA_OUT <= DMA_VALUE[31:16];	// Is [15:0] ever used ?
					end

					default: ;
				endcase
			end

			// DMA logic
			
			// DMA_TIMER is a minimum wait, so tick it even when DMA_SDRAM_BUSY
			if (DMA_TIMER)
				DMA_TIMER <= DMA_TIMER - 1'b1;
			
			if (!DMA_SDRAM_BUSY)
			begin
				if (!DMA_TIMER)
				begin
					if (DMA_STATE == DMA_STATE_BR)
					begin
						// Init: Do 68k bus request
						nBR <= 0;
						DMA_STATE <= DMA_STATE_WAIT_BG;
					end

					if (DMA_STATE == DMA_STATE_WAIT_BG)
					begin
						// Init: Wait for nBG low
						if (~nBG)
							DMA_STATE <= DMA_STATE_WAIT_AS;
					end

					if (DMA_STATE == DMA_STATE_WAIT_AS)
					begin
						// Init: Wait for nAS and nDTACK high
						if (nAS & nDTACK)
						begin
							nBR <= 1;
							nBGACK <= 0;
							DMA_STATE <= DMA_STATE_START;
						end
					end

					if (DMA_STATE == DMA_STATE_START)
					begin
						// Base state for DMA loop
						// FX68K doesn't tri-state its outputs when it releases the bus (good !)
						// So use separate busses and signals when doing DMA and switch them according to DMA_RUNNING
						if (!DMA_COUNT_RUN)
						begin
							// DMA done !
							DMA_STATE <= DMA_STATE_IDLE;	// Go back to idle
							nBGACK <= 1;			// Release bus
							DMA_RUNNING <= 0;		// Inform CDC that the transfer is finished
						end
						else
						begin
							// Working...
							case (DMA_MODE)
								DMA_COPY_CD_WORD:
								begin
									// Word copy LC8951 cache -> DMA_ADDR_A
									case(DMA_IO_CNT)
										4'd0: DMA_STATE <= DMA_STATE_CACHE_RD; // Read word from Cache
										4'd1: begin
												DMA_DATA_OUT <= DMA_RD_DATA;
												DMA_STATE <= DMA_STATE_WR; // Write word
										end

										default: DMA_STATE <= DMA_STATE_DONE;
									endcase
								end

								DMA_COPY_CD_BYTE:
								begin
									// Copy LC8951 cache -> DMA_ADDR_A odd bytes
									case(DMA_IO_CNT)
										4'd0: DMA_STATE <= DMA_STATE_CACHE_RD; // Read word from Cache
										4'd1: begin
											DMA_DATA_OUT <= {DMA_RD_DATA[7:0], DMA_RD_DATA[15:8]};
											DMA_STATE <= DMA_STATE_WR; // Write low byte
										end
										4'd2: begin
											DMA_DATA_OUT <= DMA_RD_DATA;
											DMA_STATE <= DMA_STATE_WR; // Write high byte
										end

										default: DMA_STATE <= DMA_STATE_DONE;
									endcase
								end

								DMA_COPY_WORD:
								begin
									// Word copy DMA_ADDR_A -> DMA_ADDR_B
									case(DMA_IO_CNT)
										4'd0: DMA_STATE <= DMA_STATE_RD; // Read word
										4'd1: begin
											DMA_DATA_OUT <= DMA_RD_DATA;
											DMA_STATE <= DMA_STATE_WR; // Write word
										end

										default: DMA_STATE <= DMA_STATE_DONE;
									endcase
								end

								DMA_COPY_BYTE:
								begin
									// Byte copy DMA_ADDR_A -> DMA_ADDR_B odd bytes
									case(DMA_IO_CNT)
										4'd0: DMA_STATE <= DMA_STATE_RD; // Read word
										4'd1: begin
											DMA_DATA_OUT <= {DMA_RD_DATA[7:0], DMA_RD_DATA[15:8]};
											DMA_STATE <= DMA_STATE_WR; // Write low byte
										end
										4'd2: begin
											DMA_DATA_OUT <= DMA_RD_DATA;
											DMA_STATE <= DMA_STATE_WR; // Write high byte
										end

										default: DMA_STATE <= DMA_STATE_DONE;
									endcase
								end

								DMA_FILL_VALUE:
								begin
									// Word fill from DMA_ADDR_A
									case(DMA_IO_CNT)
										4'd0: DMA_STATE <= DMA_STATE_WR;
										default: DMA_STATE <= DMA_STATE_DONE;
									endcase
								end

								default: ;
							endcase
						end
					end

					if (DMA_STATE == DMA_STATE_CACHE_RD)
					begin
						DMA_RD_DATA[15:8] <= CACHE_DOUT; // Got upper byte
						CACHE_RD_ADDR <= CACHE_RD_ADDR + 1'b1;
						DMA_TIMER <= 8'd10;	// TODO: Tune this
						DMA_STATE <= DMA_STATE_CACHE_RD_L;
					end

					if (DMA_STATE == DMA_STATE_CACHE_RD_L)
					begin
						DMA_RD_DATA[7:0] <= CACHE_DOUT;	// Got lower byte
						CACHE_RD_ADDR <= CACHE_RD_ADDR + 1'b1;
						DMA_IO_CNT <= DMA_IO_CNT + 1'b1;
						DMA_STATE <= DMA_STATE_START;
					end

					if (DMA_STATE == DMA_STATE_WR)
					begin
						DMA_WR_OUT <= 1;
						DMA_TIMER <= 8'd20;	// TODO: Tune this
						DMA_STATE <= DMA_STATE_WR_DONE;
					end

					if (DMA_STATE == DMA_STATE_WR_DONE)
					begin
						// Write done
						DMA_WR_OUT <= 0;
						DMA_ADDR_OUT <= DMA_ADDR_OUT + 2'd2;
						DMA_IO_CNT <= DMA_IO_CNT + 1'b1;
						DMA_STATE <= DMA_STATE_START;
					end

					if (DMA_STATE == DMA_STATE_RD)
					begin
						DMA_RD_OUT <= 1;
						DMA_TIMER <= 8'd20;	// TODO: Tune this
						DMA_STATE <= DMA_STATE_RD_DONE;
					end

					if (DMA_STATE == DMA_STATE_RD_DONE)
					begin
						DMA_RD_OUT <= 0;
						DMA_RD_DATA <= DMA_DATA_IN;
						DMA_ADDR_IN <= DMA_ADDR_IN + 2'd2;
						DMA_IO_CNT <= DMA_IO_CNT + 1'b1;
						DMA_STATE <= DMA_STATE_START;
					end

					if (DMA_STATE == DMA_STATE_DONE)
					begin
						DMA_COUNT_RUN <= DMA_COUNT_RUN - 1'b1;
						DMA_STATE <= DMA_STATE_START;
						DMA_IO_CNT <= 4'd0;
					end

				end
			end
		end
	end
	
	wire READING = ~nAS & M68K_RW & (M68K_ADDR[23:12] == 12'hFF0) & SYSTEM_CDx;
	wire WRITING = ~nAS & ~M68K_RW & (M68K_ADDR[23:12] == 12'hFF0) & SYSTEM_CDx;
	
	wire LC8951_RD = (READING & (M68K_ADDR[11:2] == 10'b0001_000000));	// FF0101, FF0103
	wire LC8951_WR = (WRITING & (M68K_ADDR[11:2] == 10'b0001_000000));	// FF0101, FF0103
	
	// nAS used ?
	wire TR_ZONE = (DMA_RUNNING ? (DMA_ADDR_OUT[23:20] == 4'hE) : (M68K_ADDR[23:20] == 4'hE)) & SYSTEM_CDx;

	wire TR_ZONE_RD = TR_ZONE & (DMA_RUNNING ? DMA_RD_OUT : M68K_RW & ~(nLDS & nUDS));
	wire TR_ZONE_WR = TR_ZONE & (DMA_RUNNING ? DMA_WR_OUT : ~M68K_RW & ~(nLDS & nUDS));

	wire CD_TR_SPR = (CD_TR_AREA == 3'd0) & CD_USE_SPR;
	wire CD_TR_PCM = (CD_TR_AREA == 3'd1) & CD_USE_PCM;
	wire CD_TR_Z80 = (CD_TR_AREA == 3'd4) & CD_USE_Z80;
	wire CD_TR_FIX = (CD_TR_AREA == 3'd5) & CD_USE_FIX;

	// Allow writes only if the "allow write" flag of the corresponding region is set
	assign CD_TR_WR_SPR = TR_ZONE_WR & CD_TR_SPR;
	assign CD_TR_WR_PCM = TR_ZONE_WR & CD_TR_PCM;
	assign CD_TR_WR_Z80 = TR_ZONE_WR & CD_TR_Z80;
	assign CD_TR_WR_FIX = TR_ZONE_WR & CD_TR_FIX;

	assign CD_TR_RD_FIX = TR_ZONE_RD & CD_TR_FIX;
	assign CD_TR_RD_SPR = TR_ZONE_RD & CD_TR_SPR;
	assign CD_TR_RD_Z80 = TR_ZONE_RD & CD_TR_Z80;
	assign CD_TR_RD_PCM = TR_ZONE_RD & CD_TR_PCM;

	reg [1:0] CDD_nIRQ_SR;

	always @(posedge clk_sys)
	begin
		if (!nRESET)
		begin
			CD_USE_SPR <= 0;
			CD_USE_PCM <= 0;
			CD_USE_Z80 <= 0;
			CD_USE_FIX <= 0;
			CD_SPR_EN <= 1;	// ?
			CD_FIX_EN <= 1;	// ?
			CD_VIDEO_EN <= 1;	// ?
			CD_UPLOAD_EN <= 0;
			CD_nRESET_Z80 <= 0;	// ?
			CD_nRESET_DRIVE <= 0; // ?
			HOCK <= 1;
			REG_FF0002 <= 16'h0;	// ?
			REG_FF0004 <= 0;	// ?
			nLDS_PREV <= 1;
			nUDS_PREV <= 1;
			CD_IRQ <= 1;
			CD_IRQ_FLAGS <= 3'b111;
			DMA_START <= 0;
			
			CDD_nIRQ_SR <= 2'b11;
		end
		else if (CLK_68KCLK_EN) begin
			nLDS_PREV <= nLDS;
			nUDS_PREV <= nUDS;
			CDD_nIRQ_SR <= {CDD_nIRQ_SR[0], CDD_nIRQ};
			CDC_nIRQ_PREV <= CDC_nIRQ;
			
			// Falling edge of CDD_nIRQ
			//if (CDD_nIRQ_PREV & ~CDD_nIRQ)
			if (CDD_nIRQ_SR == 2'b10)
			begin
				// Trigger CD comm. interrupt
				if (REG_FF0002[6] & REG_FF0002[4])
					CD_IRQ_FLAGS[1] <= 0;
				
				// REG_FF0002:
				// C = CD comm. interrupt
				// S = Sector ready interrupt ?
				// 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
				//                 S     S     C     C
			end
			
			// Falling edge of CDC_nIRQ
			if (CDC_nIRQ_PREV & ~CDC_nIRQ)
			begin
				// Trigger CDC interrupt (decoder or transfer end)
				if (REG_FF0002[10] & REG_FF0002[8])
					CD_IRQ_FLAGS[2] <= 0;
			end
			
			CD_IRQ <= ~&{CD_IRQ_FLAGS};
			
			// Trigger
			if (DMA_START)
				DMA_START <= 0;
			
			if (SYSTEM_CDx & ((nLDS_PREV & ~nLDS) | (nUDS_PREV & ~nUDS)))	// & PREV_nAS & ~nAS
			begin
				// Writes
				if ((M68K_ADDR[23:9] == 15'b11111111_0000000) & ~M68K_RW)
				begin
					casez ({M68K_ADDR[8:1], nUDS, nLDS})
						// FF00xx
						10'b0_0000001_00: REG_FF0002 <= M68K_DATA;			// FF0002
						10'b0_0000010_00: REG_FF0004 <= M68K_DATA[11:0];			// FF0004
						10'b0_0000111_?0: CD_IRQ_FLAGS <= CD_IRQ_FLAGS | M68K_DATA[5:3];	// FF000E
						
						10'b0_0110000_10:			// FF0061
						begin
							if (M68K_DATA[6])
							begin
								// DMA start
								DMA_START <= 1;
								case (DMA_MICROCODE[0])
									16'hFF89, 16'hFFC5:
									begin
										// Copy LC8951 cache -> DMA_ADDR_A
										// Count in words even it's really a byte copy
										// TOP-SP1 @ C119F4
										// $FF89 $FCF5 $D8A6 $F627 $03FD $FFFF
										DMA_MODE <= DMA_COPY_CD_WORD;
									end

									16'hFC2D:
									begin
										// Copy LC8951 cache -> DMA_ADDR_A odd bytes
										// FC2D
										DMA_MODE <= DMA_COPY_CD_BYTE;
									end

									16'hFE6D, 16'hFE3D:
									begin
										// Word copy DMA_ADDR_A -> DMA_ADDR_B
										// Count in words
										// TOP-SP1 @ C119D4
										// $FE6D $FCF5 $82BF $F693 $BF29 $02FD $FFFF $C515 $FCF5

										// Word copy DMA_ADDR_A -> DMA_ADDR_B
										// Different microcode, same operation ?
										// Used by UploadPRGDMAWords, UploadPalDMAWords
										// TOP-SP1 @ C0C07C
										// $FE6D $FCF5 $82BF $F693 $BF29 $02FD $FFFF $F97D $FCF5
										DMA_MODE <= DMA_COPY_WORD;
									end

									16'hF2DD, 16'hE2DD:
									begin
										// Byte copy DMA_ADDR_A -> odd bytes DMA_ADDR_B ?
										// Used by UploadFIXDMABytes, UploadPCMDMABytes, UploadZ80DMABytes
										// Count in words
											// TOP-SP1 @ C0C09A
										// $F2DD $82F6 $93DA $BE93 $DABE $2C02 $FDFF
										DMA_MODE <= DMA_COPY_BYTE;
									end

									16'hFFCD, 16'hFFDD:
									begin
										// Word fill starting at DMA_ADDR_A
										// Used by  DMAClearPalettes, DMAClearPCMDRAM?
										// Count in words
										// TOP-SP1 @ C0C09A
										// $FFCD $FCF5 $92F6 $2602 $FDFF
										DMA_MODE <= DMA_FILL_VALUE;
									end

									default: ;
								endcase
								// Other microcodes are used but only for the test mode, those can wait
								// See TOP-SP1 @ C0AB26, TOP-SP1 @ C0AB3E, TOP-SP1 @ C0AB5A
							end
						end
						10'b0_0110010_00: DMA_ADDR_A[23:16]	<= M68K_DATA[7:0];	// FF0064~FF0065
						10'b0_0110011_00: DMA_ADDR_A[15:0] <= M68K_DATA;			// FF0066~FF0067
						10'b0_0110100_00: DMA_ADDR_B[23:16] <= M68K_DATA[7:0];	// FF0068~FF0069
						10'b0_0110101_00: DMA_ADDR_B[15:0]	<= M68K_DATA;			// FF006A~FF006B
						10'b0_0110110_00: DMA_VALUE[31:16] <= M68K_DATA;	// FF006C~FF006D
						10'b0_0110111_00: DMA_VALUE[15:0] <= M68K_DATA;		// FF006E~FF006F
						10'b0_0111000_00: DMA_COUNT[31:16] <= M68K_DATA;	// FF0070~FF0071
						10'b0_0111001_00: DMA_COUNT[15:0] <= M68K_DATA;		// FF0072~FF0073
						10'b0_0111111_00: DMA_MICROCODE[0] <= M68K_DATA;	// FF007E	M68K_ADDR[4:1]
						10'b0_1000000_00: DMA_MICROCODE[1] <= M68K_DATA;	// FF0080	M68K_ADDR[4:1]
						10'b0_1000001_00: DMA_MICROCODE[2] <= M68K_DATA;	// FF0082	M68K_ADDR[4:1]
						10'b0_1000010_00: DMA_MICROCODE[3] <= M68K_DATA;	// FF0084	M68K_ADDR[4:1]
						10'b0_1000011_00: DMA_MICROCODE[4] <= M68K_DATA;	// FF0086	M68K_ADDR[4:1]
						10'b0_1000100_00: DMA_MICROCODE[5] <= M68K_DATA;	// FF0088	M68K_ADDR[4:1]
						10'b0_1000101_00: DMA_MICROCODE[6] <= M68K_DATA;	// FF008A	M68K_ADDR[4:1]
						10'b0_1000110_00: DMA_MICROCODE[7] <= M68K_DATA;	// FF008C	M68K_ADDR[4:1]
						10'b0_1000111_00: DMA_MICROCODE[8] <= M68K_DATA;	// FF008E	M68K_ADDR[4:1]
						
						// FF01xx
						10'b1_0000010_?0: CD_TR_AREA <= M68K_DATA[2:0];		// FF0105 Upload area select
						10'b1_0001000_?0: CD_SPR_EN <= ~M68K_DATA[0];	// FF0111 REG_DISBLSPR
						10'b1_0001010_?0: CD_FIX_EN <= ~M68K_DATA[0];	// FF0115 REG_DISBLFIX
						10'b1_0001100_?0: CD_VIDEO_EN <= M68K_DATA[0];	// FF0119 REG_ENVIDEO
						10'b1_0010000_?0: CD_USE_SPR <= 1;	// FF0121 REG_UPMAPSPR
						10'b1_0010001_?0: CD_USE_PCM <= 1;	// FF0123 REG_UPMAPPCM
						10'b1_0010011_?0: CD_USE_Z80 <= 1;	// FF0127 REG_UPMAPZ80
						10'b1_0010100_?0: CD_USE_FIX <= 1;	// FF0129 REG_UPMAPFIX
						10'b1_0100000_?0: CD_USE_SPR <= 0;	// FF0141 REG_UPUNMAPSPR
						10'b1_0100001_?0: CD_USE_PCM <= 0;	// FF0143 REG_UPUNMAPSPR
						10'b1_0100011_?0: CD_USE_Z80 <= 0;	// FF0147 REG_UPUNMAPSPR
						10'b1_0100100_?0: CD_USE_FIX <= 0;	// FF0149 REG_UPUNMAPSPR
						10'b1_0110001_10: CDD_DIN <= M68K_DATA[3:0];		// FF0163 REG_CDDOUTPUT
						10'b1_0110010_10: HOCK <= M68K_DATA[0];			// FF0165 REG_CDDCTRL
						10'b1_0110111_?0: CD_UPLOAD_EN <= M68K_DATA[0];		// FF016F
						10'b1_1000000_?0: CD_nRESET_DRIVE <= M68K_DATA[0];	// FF0181
						10'b1_1000001_?0: CD_nRESET_Z80 <= M68K_DATA[0];	// FF0183
						10'b1_1010000_?0: CD_BANK_SPR <= M68K_DATA[1:0];	// FF01A1 REG_SPRBANK
						10'b1_1010001_?0: CD_BANK_PCM <= M68K_DATA[0];	// FF01A3 REG_PCMBANK
						default:;
					endcase
				end
				else if ((M68K_ADDR[23:20] == 4'hE) & ~M68K_RW)
				begin
					// Upload zone
					// Is this buffered or is the write directy forwarded to memory ?
					CD_TR_WR_DATA <= M68K_DATA;
					CD_TR_WR_ADDR <= M68K_ADDR[19:1];
				end
			end
		end
	end
	
	// 1111:JP, 1110:US, 1101: EU
	wire [3:0] CD_JUMPERS = {2'b11, CD_REGION};
	
	wire [7:0] CD_IRQ_VECTOR = (M68K_ADDR[2:1] == 2'd3) ? 8'd25 : // Timer $64
									(M68K_ADDR[2:1] == 2'd2) & ~CD_IRQ_FLAGS[0] ? 8'd23 :
									(M68K_ADDR[2:1] == 2'd2) & ~CD_IRQ_FLAGS[1] ? 8'd22 : // CD comm.   $58
									(M68K_ADDR[2:1] == 2'd2) & ~CD_IRQ_FLAGS[2] ? 8'd21 : // CD decoder $54
									(M68K_ADDR[2:1] == 2'd1) ? 8'd26 : // VBlank $68
										8'd24;	// Spurious interrupt, should not happen

	function [15:0] bit_reverse;
		input [15:0] a;
		begin
			bit_reverse = { a[0],a[1],a[2],a[3],a[4],a[5],a[6],a[7],a[8],a[9],a[10],a[11],a[12],a[13],a[14],a[15] };
		end
	endfunction

	assign CD_VBLANK_IRQ_EN = &{REG_FF0004[5:4]};

	assign M68K_DATA = (SYSTEM_CDx & ~nAS & M68K_RW & IACK) ? {8'h00, CD_IRQ_VECTOR} :		// Vectored interrupt handler
							(READING & {M68K_ADDR[11:1], 1'b0} == 12'h004) ? {4'h0, REG_FF0004} :
							(READING & {M68K_ADDR[11:1], 1'b0} == 12'h11C) ? {3'b110, CD_LID, CD_JUMPERS, 8'h00} :	// Top mech
							(READING & {M68K_ADDR[11:1], 1'b0} == 12'h160) ? {11'b00000000_000, CDCK, CDD_DOUT} :	// REG_CDDINPUT
							(READING & {M68K_ADDR[11:1], 1'b0} == 12'h188) ? bit_reverse(CD_AUDIO_L) :	// CDDA L
							(READING & {M68K_ADDR[11:1], 1'b0} == 12'h18A) ? bit_reverse(CD_AUDIO_R) :	// CDDA R
							(LC8951_RD) ? {8'h00, LC8951_DOUT} :
							16'bzzzzzzzz_zzzzzzzz;
endmodule
