//
// sdram.v
//
// Static RAM controller implementation using SDRAM MT48LC16M16A2
//
// Copyright (c) 2015,2016 Sorgelig
//
// Some parts of SDRAM code used from project:
// http://hamsterworks.co.nz/mediawiki/index.php/Simple_SDRAM_Controller
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version. 
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// ------------------------------------------
//
// furrtek 2019-01-24 : Added ugly burst reading
//

module sdram
(
	input             init,        // reset to initialize RAM
	input             clk,         // clock ~100MHz
											 //
											 // SDRAM_* - signals to the MT48LC16M16 chip
	inout  reg [15:0] SDRAM_DQ,    // 16 bit bidirectional data bus
	output reg [12:0] SDRAM_A,     // 13 bit multiplexed address bus
	output            SDRAM_DQML,  // two byte masks
	output            SDRAM_DQMH,  // 
	output reg  [1:0] SDRAM_BA,    // two banks
	output            SDRAM_nCS,   // a single chip select
	output            SDRAM_nWE,   // write enable
	output            SDRAM_nRAS,  // row address select
	output            SDRAM_nCAS,  // columns address select
	output            SDRAM_CKE,   // clock enable
	input             SDRAM_EN,    // clock enable
											 //
	input       [1:0] wtbt,        // 16bit mode:  bit1 - write high byte, bit0 - write low byte,
											 // 8bit mode:  2'b00 - use addr[0] to decide which byte to write
											 // Ignored while reading.
											 //
	input             sel,
	input      [25:0] addr,        // 25 bit address for 8bit mode. addr[0] = 0 for 16bit mode for correct operations.
	output reg [63:0] dout, 		 // data output to cpu
	input      [15:0] din,         // data input from cpu
	input             we,          // cpu requests write
	input             rd,          // cpu requests read
	input					rd_type,		 // 0=Single read, 1=Four-word burst read
	output reg			ready
);

assign SDRAM_nCS  = command[3];
assign SDRAM_nRAS = command[2];
assign SDRAM_nCAS = command[1];
assign SDRAM_nWE  = command[0];
assign SDRAM_CKE  = 1;
assign {SDRAM_DQMH,SDRAM_DQML} = SDRAM_A[12:11];


// Burst length = 4
localparam BURST_LENGTH        = 4;
localparam BURST_CODE          = (BURST_LENGTH == 8) ? 3'b011 : (BURST_LENGTH == 4) ? 3'b010 : (BURST_LENGTH == 2) ? 3'b001 : 3'b000;  // 000=1, 001=2, 010=4, 011=8
localparam ACCESS_TYPE         = 1'b0;     // 0=sequential, 1=interleaved
localparam CAS_LATENCY         = 3'd2;     // 2 for < 100MHz, 3 for >100MHz
localparam OP_MODE             = 2'b00;    // only 00 (standard operation) allowed
localparam NO_WRITE_BURST      = 1'b1;     // 0= write burst enabled, 1=only single access write
localparam MODE                = {3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_CODE};

localparam sdram_startup_cycles= 14'd12100;// 100us, plus a little more, @ 100MHz
localparam cycles_per_refresh  = 14'd780;  // (64000*100)/8192-1 Calc'd as (64ms @ 100MHz)/8192 rose
localparam startup_refresh_max = 14'b11111111111111;

// SDRAM commands
localparam CMD_INHIBIT         = 4'b1111;
localparam CMD_NOP             = 4'b0111;
localparam CMD_ACTIVE          = 4'b0011;
localparam CMD_READ            = 4'b0101;
localparam CMD_WRITE           = 4'b0100;
localparam CMD_BURST_TERMINATE = 4'b0110;
localparam CMD_PRECHARGE       = 4'b0010;
localparam CMD_AUTO_REFRESH    = 4'b0001;
localparam CMD_LOAD_MODE       = 4'b0000;

reg [13:0] refresh_count = startup_refresh_max - sdram_startup_cycles;
reg  [3:0] command = CMD_INHIBIT;

typedef enum
{
	STATE_STARTUP,
	STATE_WAIT,
	STATE_RW,
	STATE_IDLE,
	STATE_IDLE_1,
	STATE_IDLE_2,
	STATE_IDLE_3,
	STATE_IDLE_4,
	STATE_IDLE_5
} state_t;

always @(posedge clk) begin
	reg old_we, old_rd;
	reg [CAS_LATENCY+BURST_LENGTH-1:0] data_ready_delay;

	reg [15:0] new_data;
	reg  [1:0] new_wtbt;
	reg        new_we;
	reg        new_rd;
	reg		  new_rd_type;
	reg        saved_we = 1;
	reg        saved_burst;
	reg [25:0] saved_addr;
	state_t    state = STATE_STARTUP;

	refresh_count <= refresh_count+1'b1;

	data_ready_delay <= data_ready_delay>>1;

	if(data_ready_delay[0]) dout[15:0]  <= SDRAM_DQ;
	if(data_ready_delay[1]) dout[31:16] <= SDRAM_DQ;
	if(data_ready_delay[2]) dout[47:32] <= SDRAM_DQ;
	if(data_ready_delay[3]) dout[63:48] <= SDRAM_DQ;

	if(data_ready_delay[0] &  saved_burst) ready <= 1;
	if(data_ready_delay[3] & ~saved_burst) ready <= 1;
	if(data_ready_delay[3] & ~saved_burst) data_ready_delay <= 0;

	SDRAM_DQ   <= 16'bZ;

	if(SDRAM_EN) begin
		command <= CMD_NOP;
		case (state)
			STATE_STARTUP: begin
				//------------------------------------------------------------------------
				//-- This is the initial startup state, where we wait for at least 100us
				//-- before starting the start sequence
				//-- 
				//-- The initialisation is sequence is 
				//--  * de-assert SDRAM_CKE
				//--  * 100us wait, 
				//--  * assert SDRAM_CKE
				//--  * wait at least one cycle, 
				//--  * PRECHARGE
				//--  * wait 2 cycles
				//--  * REFRESH, 
				//--  * tREF wait
				//--  * REFRESH, 
				//--  * tREF wait 
				//--  * LOAD_MODE_REG 
				//--  * 2 cycles wait
				//------------------------------------------------------------------------
				SDRAM_A    <= 0;
				SDRAM_BA   <= 0;

				// All the commands during the startup are NOPS, except these
				if(refresh_count == startup_refresh_max-31) begin
					// ensure all rows are closed
					command     <= CMD_PRECHARGE;
					SDRAM_A[10] <= 1;  // all banks
					SDRAM_BA    <= 2'b00;
				end else if (refresh_count == startup_refresh_max-23) begin
					// these refreshes need to be at least tREF (66ns) apart
					command     <= CMD_AUTO_REFRESH;
				end else if (refresh_count == startup_refresh_max-15) 
					command     <= CMD_AUTO_REFRESH;
				else if (refresh_count == startup_refresh_max-7) begin
					// Now load the mode register
					command     <= CMD_LOAD_MODE;
					SDRAM_A     <= MODE;
				end

				//------------------------------------------------------
				//-- if startup is complete then go into idle mode,
				//-- get prepared to accept a new command, and schedule
				//-- the first refresh cycle
				//------------------------------------------------------
				if (!refresh_count) begin
					state   <= STATE_IDLE;
					ready <= 1;
					refresh_count <= 0;
				end
			end

			STATE_IDLE_5: state <= STATE_IDLE_4;
			STATE_IDLE_4: state <= STATE_IDLE_3;
			STATE_IDLE_3: state <= STATE_IDLE_2;
			STATE_IDLE_2: state <= STATE_IDLE_1;
			STATE_IDLE_1: begin
				state      <= STATE_IDLE;
				// mask possible refresh to reduce colliding.
				if (refresh_count > cycles_per_refresh) begin
					//------------------------------------------------------------------------
					//-- Start the refresh cycle. 
					//-- This tasks tRFC (66ns), so 7 idle cycles are needed @ 120MHz
					//------------------------------------------------------------------------
					state    <= STATE_IDLE_5;
					command  <= CMD_AUTO_REFRESH;
					refresh_count <= refresh_count - cycles_per_refresh + 1'd1;
				end
			end

			STATE_IDLE: begin
				if (refresh_count > (cycles_per_refresh << 1)) begin
					// Priority is to issue a refresh if one is outstanding
					state <= STATE_IDLE_1;
				end else if (new_rd | new_we) begin
					// Start new access cycle
					new_we   <= 0;
					new_rd   <= 0;
					saved_addr<= addr;
					saved_we  <= new_we;
					saved_burst<= ~new_we & new_rd_type;
					state    <= STATE_WAIT;
					command  <= CMD_ACTIVE;
					SDRAM_A  <= addr[22:10];
					SDRAM_BA <= addr[24:23];
				end
			end

			STATE_WAIT: state <= STATE_RW;

			STATE_RW: begin
				SDRAM_A     <= {~saved_we ? 2'b00 : new_wtbt ? ~new_wtbt : {saved_addr[0], ~saved_addr[0]}, 1'b1, saved_addr[25], saved_addr[9:1]};	// Enable auto-precharge
				state       <= saved_burst ? STATE_IDLE_5 : STATE_IDLE_2;
				if(saved_we) begin
					command  <= CMD_WRITE;
					SDRAM_DQ <= new_wtbt ? new_data : {new_data[7:0], new_data[7:0]};
					ready    <= 1;
				end
				else begin
					command  <= CMD_READ;
					data_ready_delay[CAS_LATENCY+BURST_LENGTH-1] <= 1;
				end
			end
		endcase

		if (init) begin
			state <= STATE_STARTUP;
			refresh_count <= startup_refresh_max - sdram_startup_cycles;
		end

		old_we <= we;
		if (we & ~old_we & sel) {ready, new_we, new_data, new_wtbt} <= {1'b0, 1'b1, din, wtbt};

		old_rd <= rd;
		if (rd & ~old_rd & sel) {ready, new_rd, new_rd_type} <= {1'b0, 1'b1, rd_type};
	end
	else begin
		ready <= 1;
		dout <= '0;
		SDRAM_A <= 'Z;
		SDRAM_BA <= 'Z;
		command <= 'Z;
	end
end

endmodule
