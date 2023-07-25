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

// This module handles the CDD 4-bit communication bus, TOC readback and keeps
// track of the current MSF
// The protocol is very similar (if not identical) to the one used by the Mega CD drive

module cd_drive(
	input nRESET,	// System reset OR drive reset
	input HOCK,
	output reg CDCK,
	input [3:0] CDD_DIN,
	output reg [3:0] CDD_DOUT,
	output reg CDD_nIRQ,
	
	input clk_sys,
	input [39:0] STATUS_IN,
	input STATUS_LATCH,
	output reg [39:0] COMMAND_DATA,
	output reg COMMAND_SEND
);

	// Command codes
	parameter CMD_NOP=4'd0, CMD_STOP=4'd1, CMD_TOC=4'd2, CMD_PLAY=4'd3, CMD_SEEK=4'd4, CMD_PAUSE=4'd6, CMD_RESUME=4'd7,
		CMD_FFW=4'd8, CMD_REW=4'd9, CMD_CLOSE=4'd12, CMD_OPEN=4'd13;

	// TOC sub-commands
	parameter TOC_ABSPOS=4'd0, TOC_RELPOS=4'd1, TOC_TRACK=4'd2, TOC_LENGTH=4'd3, TOC_FIRSTLAST=4'd4, TOC_START=4'd5,
		TOC_ERROR=4'd6;
	
	// Status codes
	parameter STAT_STOPPED=4'd0, STAT_PLAYING=4'd1, STAT_READTOC=4'd9;
	
	// Current TOC sub-command implementation:
	// 0: Get position
	//		Unimplemented
	// 1: Get position relative
	//		Unimplemented
	// 2: Get track number
	//		Unimplemented
	// 3: Get CD length: sd_req_type = 16'hD100
	//		0: M
	//		1: S
	//		2: F
	// 4: Get first/last: sd_req_type = 16'hD000
	//		0: First track # BCD
	//		1: Last track # BCD
	// 5: Get track start: sd_req_type = 16'hD2nn
	//		0: M
	//		1: S
	//		2: F
	//		3: Type
	// 6: Get last error
	//		Unimplemented

	reg [8:0] CLK_DIV;		// SLOW THE FUCK DOWN
	reg [11:0] IRQ_TIMER;
	reg [3:0] DOUT_COUNTER;	// 0~10
	reg [3:0] DIN_COUNTER;	// 0~10, 11 is special code for processing
	
	reg [3:0] STATUS_DATA [10];
	reg STATUS_LATCH_OLD, STATUS_PENDING;
	
	reg HOCK_PREV;
	reg [1:0] COMM_STATE;	// 0~2
	reg COMM_RUN;

	always @(posedge clk_sys)
	begin
		if (!nRESET)
		begin
			CLK_DIV <= 9'd0;
			IRQ_TIMER <= 12'd0;
			DOUT_COUNTER <= 4'd0;
			DIN_COUNTER <= 4'd0;
			HOCK_PREV <= 0;
			CDCK <= 1;
			COMM_STATE <= 2'd0;
			COMM_RUN <= 0;
			CDD_nIRQ <= 1;
			STATUS_DATA[0] <= STAT_STOPPED;
			STATUS_DATA[1] <= 4'd0;
			STATUS_DATA[2] <= 4'd0;
			STATUS_DATA[3] <= 4'd0;
			STATUS_DATA[4] <= 4'd0;
			STATUS_DATA[5] <= 4'd0;
			STATUS_DATA[6] <= 4'd0;
			STATUS_DATA[7] <= 4'd0;
			STATUS_DATA[8] <= 4'd0;
			STATUS_DATA[9] <= 4'd0;
			STATUS_PENDING <= 0;
			STATUS_LATCH_OLD <= 0;
			COMMAND_SEND <= 0;
		end
		else
		begin

			STATUS_LATCH_OLD <= STATUS_LATCH;
			if (~STATUS_LATCH_OLD & STATUS_LATCH) begin
				STATUS_PENDING <= 1;
			end

			COMMAND_SEND <= 0;

			// This simulates the Sony CDD MCU, so it must be quite slow
			// Here it "runs" at clk_sys/192=48M/192=250kHz
			
			if (CLK_DIV == 9'd192-1)
			begin
				CLK_DIV <= 9'd0;
				
				HOCK_PREV <= HOCK;
				
				// Fire CDD comm. IRQ at 64Hz
				// Does it switch to 75Hz when playing ?
				if (IRQ_TIMER == 12'd3906-1)
				begin
					IRQ_TIMER <= 12'd0;
					CDD_nIRQ <= 0;
					COMM_STATE <= 2'd0;
					COMM_RUN <= 0;
				end
				else
				begin
					// Retry whatever happens
					if (IRQ_TIMER == 12'd1953-1)
						CDD_nIRQ <= 1;
						
					IRQ_TIMER <= IRQ_TIMER + 1'b1;
				end

				if (STATUS_PENDING & (DOUT_COUNTER == 4'd10)) begin
					STATUS_PENDING <= 0;
					STATUS_DATA[0] <= STATUS_IN[ 3: 0];
					STATUS_DATA[1] <= STATUS_IN[ 7: 4];
					STATUS_DATA[2] <= STATUS_IN[11: 8];
					STATUS_DATA[3] <= STATUS_IN[15:12];
					STATUS_DATA[4] <= STATUS_IN[19:16];
					STATUS_DATA[5] <= STATUS_IN[23:20];
					STATUS_DATA[6] <= STATUS_IN[27:24];
					STATUS_DATA[7] <= STATUS_IN[31:28];
					STATUS_DATA[8] <= STATUS_IN[35:32];
					STATUS_DATA[9] <= STATUS_IN[39:36];
				end

				if (~HOCK & ~CDD_nIRQ) begin
					CDD_nIRQ <= 1;		// Comm. started ok, ack
					COMM_RUN <= 1;
					DOUT_COUNTER <= 4'd0;
					DIN_COUNTER <= 4'd0;
				end

				if (COMM_RUN)
				begin
					if (DOUT_COUNTER != 4'd10)
					begin
						// CDD to HOST
						
						if (COMM_STATE == 2'd0)
						begin
							// Put data on bus
							CDD_DOUT <= STATUS_DATA[DOUT_COUNTER];
							CDCK <= 0;
							COMM_STATE <= 2'd1;
						end
						else if (COMM_STATE == 2'd1)
						begin
							// Wait for HOCK high
							if (~HOCK_PREV & HOCK)
							begin
								CDCK <= 1;
								COMM_STATE <= 2'd2;
								// Escape from CDD -> HOST mode at last word
								if (DOUT_COUNTER == 4'd9)
								begin
									DOUT_COUNTER <= 4'd10;
									COMM_STATE <= 2'd1;
								end
							end
						end
						else if (COMM_STATE == 2'd2)
						begin
							// Wait for HOCK low
							if (HOCK_PREV & ~HOCK)
							begin
								DOUT_COUNTER <= DOUT_COUNTER + 1'b1;
								COMM_STATE <= 2'd0;
							end
						end
						
					end
					else if (DIN_COUNTER < 4'd10)
					begin
						// HOST to CDD
						
						if (COMM_STATE == 2'd0)
						begin
							// Wait for HOCK rising edge
							if (~HOCK_PREV & HOCK)
							begin
								case (DIN_COUNTER)
									4'd0: COMMAND_DATA[ 3: 0] <= CDD_DIN;
									4'd1: COMMAND_DATA[ 7: 4] <= CDD_DIN;
									4'd2: COMMAND_DATA[11: 8] <= CDD_DIN;
									4'd3: COMMAND_DATA[15:12] <= CDD_DIN;
									4'd4: COMMAND_DATA[19:16] <= CDD_DIN;
									4'd5: COMMAND_DATA[23:20] <= CDD_DIN;
									4'd6: COMMAND_DATA[27:24] <= CDD_DIN;
									4'd7: COMMAND_DATA[31:28] <= CDD_DIN;
									4'd8: COMMAND_DATA[35:32] <= CDD_DIN;
									4'd9: COMMAND_DATA[39:36] <= CDD_DIN;
									default: ;
								endcase
								CDCK <= 1;
								DIN_COUNTER <= DIN_COUNTER + 1'b1;
								COMM_STATE <= 2'd1;
							end
						end
						else if (COMM_STATE == 2'd1)
						begin
							// Wait for HOCK falling edge
							if (HOCK_PREV & ~HOCK)
							begin
								CDCK <= 0;
								COMM_STATE <= 2'd0;
							end
						end
						
					end
					else if (DIN_COUNTER == 4'd10)
					begin
						// Comm frame just ended, do this just once
						COMMAND_SEND <= 1;
						COMM_RUN <= 0;
					end
					
				end
			end
			else
				CLK_DIV <= CLK_DIV + 1'b1;
		end
	end
endmodule
