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
                                  //
   input       [1:0] wtbt,        // 16bit mode:  bit1 - write high byte, bit0 - write low byte,
                                  // 8bit mode:  2'b00 - use addr[0] to decide which byte to write
                                  // Ignored while reading.
                                  //
   input      [24:0] addr,        // 25 bit address for 8bit mode. addr[0] = 0 for 16bit mode for correct operations.
   output reg [63:0] dout, 		 // data output to cpu
   input      [15:0] din,         // data input from cpu
   input             we,          // cpu requests write
   input             rd,          // cpu requests read
	input					rd_type,		 // 0=Single read, 1=Four-word burst read
   //output reg        ready_first, // dout_a is valid. Ready to accept new read/write.
   //output reg        ready_fourth
	output reg			ready
);

//wire [15:0] dout_first;
assign SDRAM_nCS  = command[3];
assign SDRAM_nRAS = command[2];
assign SDRAM_nCAS = command[1];
assign SDRAM_nWE  = command[0];
assign SDRAM_CKE  = 1;
assign {SDRAM_DQMH,SDRAM_DQML} = SDRAM_A[12:11];


//assign dout = {dout_first, data_second, data_third, data_fourth};
//assign dout = {data_first, data_second, data_third, data_fourth};
//assign dout_first = latched_first ? data_first : SDRAM_DQ;

// Burst length = 4
localparam BURST_LENGTH        = 3'b010;   // 000=1, 001=2, 010=4, 011=8
localparam ACCESS_TYPE         = 1'b0;     // 0=sequential, 1=interleaved
localparam CAS_LATENCY         = 3'd3;     // 2 for < 100MHz, 3 for >100MHz
localparam OP_MODE             = 2'b00;    // only 00 (standard operation) allowed
localparam NO_WRITE_BURST      = 1'b1;     // 0= write burst enabled, 1=only single access write
localparam MODE                = {3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH};

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
reg [24:0] save_addr;

/*reg        latched_first;
reg [15:0] data_first;
reg [15:0] data_second;
reg [15:0] data_third;
reg [15:0] data_fourth;*/

typedef enum
{
	STATE_STARTUP,
	STATE_OPEN_1, STATE_OPEN_2,
	STATE_WRITE,
	STATE_READ,
	STATE_IDLE,	  STATE_IDLE_1, STATE_IDLE_2, STATE_IDLE_3,
	STATE_IDLE_4, STATE_IDLE_5, STATE_IDLE_6, STATE_IDLE_7,
	STATE_IDLE_8
} state_t;

always @(posedge clk) begin
	reg old_we, old_rd;
	reg [CAS_LATENCY+3:0] data_ready_delay;

	reg [15:0] new_data;
	reg  [1:0] new_wtbt;
	reg        new_we;
	reg        new_rd;
	reg		  new_rd_type;
	reg        save_we = 1;

	state_t state = STATE_STARTUP;

	command <= CMD_NOP;
	refresh_count <= refresh_count+1'b1;

	data_ready_delay <= {1'b0, data_ready_delay[CAS_LATENCY+3:1]};

	case (data_ready_delay)
		/*7'b0010000: begin
			latched_first <= 1'b0;
			ready_first <= 1'b1;
		end*/
		7'b0001000: begin
			// CAS_LATENCY just went by, data is ready to be latched
			//latched_first <= 1'b1;
			
			//ready_first <= 1'b1;
			if (~new_rd_type) ready <= 1;
			dout[63:48] <= SDRAM_DQ;
		end
		7'b0000100: begin
			dout[47:32] <= SDRAM_DQ;
		end
		7'b0000010: begin
			dout[31:16] <= SDRAM_DQ;
		end
		7'b0000001: begin
			if (new_rd_type)
			begin
				//ready_fourth <= 1'b1;
				dout[15:0] <= SDRAM_DQ;
				ready <= 1;
			end
		end
		default:;
	endcase

	SDRAM_DQ   <= 16'bZ;

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
				//ready_first   <= 1;
				//ready_fourth   <= 1;
				ready <= 1;
				refresh_count <= 0;
			end
		end

		STATE_IDLE_8: state <= STATE_IDLE_7;
		STATE_IDLE_7: state <= STATE_IDLE_6;
		STATE_IDLE_6: state <= STATE_IDLE_5;
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
				state    <= STATE_IDLE_8;
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
				save_addr<= addr;
				save_we  <= new_we;
				state    <= STATE_OPEN_1;
				command  <= CMD_ACTIVE;
				SDRAM_A  <= addr[22:10];
				SDRAM_BA <= addr[24:23];
			end
		end

		// ACTIVE-to-READ or WRITE delay >20ns (-75)
		STATE_OPEN_1: state <= STATE_OPEN_2;
		STATE_OPEN_2: begin
			SDRAM_A     <= {save_we & (new_wtbt ? ~new_wtbt[1] : save_addr[0]), save_we & (new_wtbt ? ~new_wtbt[0] : ~save_addr[0]), 2'b10, save_addr[9:1]};	// Enable auto-precharge
			state       <= save_we ? STATE_WRITE : STATE_READ;
		end

		STATE_READ: begin
			// Wait longer before returning to STATE_IDLE for 4-word burst reads
			state       <= new_rd_type ? STATE_IDLE_7 : STATE_IDLE_4;
			command     <= CMD_READ;
			// Schedule reading the data values off the bus
			data_ready_delay[CAS_LATENCY+3] <= 1;
		end

		STATE_WRITE: begin
			state       <= STATE_IDLE_5;
			command     <= CMD_WRITE;
			SDRAM_DQ    <= new_wtbt ? new_data : {new_data[7:0], new_data[7:0]};
			//ready_first <= 1;
			ready <= 1;
		end
	endcase

	if (init) begin
		state <= STATE_STARTUP;
		refresh_count <= startup_refresh_max - sdram_startup_cycles;
	end

	old_we <= we;
	if (we & ~old_we) begin
		// Request for write
		//{ready_first, new_we, new_data, new_wtbt} <= {1'b0, 1'b1, din, wtbt};
		{ready, new_we, new_data, new_wtbt} <= {1'b0, 1'b1, din, wtbt};
	end

	old_rd <= rd;
	if (rd & ~old_rd) begin
		// Request for read
		//if (ready_first & ~save_we & (save_addr[24:1] == addr[24:1]))
		if (ready & ~save_we & (save_addr[24:1] == addr[24:1]))
			save_addr <= addr;
		else
			{ready, new_rd, new_rd_type} <= {1'b0, 1'b1, rd_type};
			//{ready_first, ready_fourth, new_rd, new_rd_type} <= {1'b0, 1'b0, 1'b1, rd_type};
	end
end

endmodule
