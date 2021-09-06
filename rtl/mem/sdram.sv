//
// sdram.v
//
// Static RAM controller implementation using SDRAM MT48LC16M16A2
//
// Copyright (c) 2015-2019 Sorgelig
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
// Sorgelig 2019-08   : rework, support mem copy and larger chips.
//

module sdram
(
	input             init,        // reset to initialize RAM
	input             clk,         // clock ~100MHz

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
	output            SDRAM_CLK,
	input             SDRAM_EN,    // clock enable

	input             sel,
	input      [26:1] addr,        // 25 bit address for 8bit mode. addr[0] = 0 for 16bit mode for correct operations.
	output reg [63:0] dout,        // data output to cpu
	input      [15:0] din,         // data input from cpu
	input             wr,          // request write
	input       [1:0] bs,          // bit1 - write high byte, bit0 - write low byte, Ignored while reading.
	input             rd,          // request read
	input             burst,       // 0 = Single read, 1 = Four-word burst read
	output reg        ready,

	input             cpsel,
	input      [26:1] cpaddr,
	input      [15:0] cpdin,
	output reg        cprd,
	input             cpreq,
	output reg        cpbusy
);

assign SDRAM_nCS  = chip;
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
wire [2:0] CMD_NOP             = 3'b111;
wire [2:0] CMD_ACTIVE          = 3'b011;
wire [2:0] CMD_READ            = 3'b101;
wire [2:0] CMD_WRITE           = 3'b100;
wire [2:0] CMD_PRECHARGE       = 3'b010;
wire [2:0] CMD_AUTO_REFRESH    = 3'b001;
wire [2:0] CMD_LOAD_MODE       = 3'b000;

reg [13:0] refresh_count = startup_refresh_max - sdram_startup_cycles;
reg  [2:0] command;
reg        chip;

localparam STATE_STARTUP =  0;
localparam STATE_WAIT    =  1;
localparam STATE_RW      =  2;
localparam STATE_WAITCP  =  3;
localparam STATE_CP      =  4;
localparam STATE_IDLE    =  5;
localparam STATE_IDLE_1  =  6;
localparam STATE_IDLE_2  =  7;
localparam STATE_IDLE_3  =  8;
localparam STATE_IDLE_4  =  9;
localparam STATE_IDLE_5  = 10;
localparam STATE_RFSH    = 11;


always @(posedge clk) begin
	reg [CAS_LATENCY+BURST_LENGTH-1:0] data_ready_delay;

	reg        saved_wr;
	reg        saved_burst;
	reg [12:0] cas_addr;
	reg [15:0] saved_data;
	reg  [8:0] cpcnt;
	reg        old_cpreq = 0;
	reg  [3:0] state = STATE_STARTUP;

	refresh_count <= refresh_count+1'b1;

	data_ready_delay <= data_ready_delay>>1;

	if(data_ready_delay[3:0]) dout <= {dout[47:0], SDRAM_DQ};

	if(data_ready_delay[0] &  saved_burst) ready <= 1;
	if(data_ready_delay[3] & ~saved_burst) ready <= 1;
	if(data_ready_delay[3] & ~saved_burst) data_ready_delay <= 0;

	SDRAM_DQ <= 16'bZ;

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

				if (refresh_count == (startup_refresh_max-64)) chip <= 0;
				if (refresh_count == (startup_refresh_max-32)) chip <= 1;

				// All the commands during the startup are NOPS, except these
				if (refresh_count == startup_refresh_max-63 || refresh_count == startup_refresh_max-31) begin
					// ensure all rows are closed
					command     <= CMD_PRECHARGE;
					SDRAM_A[10] <= 1;  // all banks
					SDRAM_BA    <= 2'b00;
				end
				if (refresh_count == startup_refresh_max-55 || refresh_count == startup_refresh_max-23) begin
					// these refreshes need to be at least tREF (66ns) apart
					command     <= CMD_AUTO_REFRESH;
				end
				if (refresh_count == startup_refresh_max-47 || refresh_count == startup_refresh_max-15) begin
					command     <= CMD_AUTO_REFRESH;
				end
				if (refresh_count == startup_refresh_max-39 || refresh_count == startup_refresh_max-7) begin
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
					ready   <= 1;
					refresh_count <= 0;
				end
				cpbusy <= 0;
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
					state    <= STATE_RFSH;
					command  <= CMD_AUTO_REFRESH;
					refresh_count <= refresh_count - cycles_per_refresh + 1'd1;
					chip     <= 0;
				end
			end
			STATE_RFSH: begin
				state    <= STATE_IDLE_5;
				command  <= CMD_AUTO_REFRESH;
				chip     <= 1;
			end

			STATE_IDLE: begin
				if (refresh_count > (cycles_per_refresh << 1)) begin
					// Priority is to issue a refresh if one is outstanding
					state <= STATE_IDLE_1;
				end else if (rd | wr) begin
					if(sel) begin
						{cas_addr[12:9],SDRAM_BA,SDRAM_A,cas_addr[8:0]} <= {~wr ? 2'b00 : ~bs, 1'b1, addr[25:1]};
						chip       <= addr[26];
						saved_data <= din;
						saved_wr   <= wr;
						saved_burst<= ~wr & burst;
						command    <= CMD_ACTIVE;
						state      <= STATE_WAIT;
						ready      <= 0;
					end
					else if (refresh_count > cycles_per_refresh) begin
						// Other SDRAM is requested, so we can refresh now
						state <= STATE_IDLE_1;
					end
				end
				else begin
					cpbusy <= 0;
					cprd   <= 0;
					old_cpreq <= cpreq;
					if(~old_cpreq & cpreq & cpsel) begin
						{cas_addr[12:9],SDRAM_BA,SDRAM_A,cas_addr[8:0]} <= {2'b00, 1'b0, cpaddr[25:1]};
						chip    <= cpaddr[26];
						cpbusy  <= 1;
						cpcnt   <= 511;
						command <= CMD_ACTIVE;
						state   <= STATE_WAITCP;
						cprd    <= 1;
					end
				end
			end

			STATE_WAIT: state <= STATE_RW;
			STATE_RW: begin
				state   <= saved_burst ? STATE_IDLE_5 : STATE_IDLE_2;
				SDRAM_A <= cas_addr;
				if(saved_wr) begin
					command  <= CMD_WRITE;
					SDRAM_DQ <= saved_data;
					ready    <= 1;
				end
				else begin
					command  <= CMD_READ;
					data_ready_delay[CAS_LATENCY+BURST_LENGTH-1] <= 1;
				end
			end
			
			STATE_WAITCP: begin
				state <= STATE_CP;
			end

			STATE_CP: begin
				SDRAM_A       <= {2'b00, !cpcnt, cas_addr[9:0]};
				cas_addr[8:0] <= cas_addr[8:0] + 1'd1;
				cpcnt         <= cpcnt - 1'd1;
				command       <= CMD_WRITE;
				SDRAM_DQ      <= cpdin;
				if(!cpcnt) begin
					state      <= STATE_IDLE_2;
					cprd       <= 0;
				end
			end
		endcase

		if (init) begin
			state <= STATE_STARTUP;
			refresh_count <= startup_refresh_max - sdram_startup_cycles;
		end
	end
	else begin
		ready <= 1;
		cpbusy <= 0;
		cprd <= 0;
		dout <= '0;
		SDRAM_A <= 0;
		SDRAM_BA <= 0;
		command <= 0;
		chip <= 0;
	end
end

altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(clk),
	.dataout(SDRAM_CLK),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);
 
endmodule
