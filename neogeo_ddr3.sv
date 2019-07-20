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

// Notes:
// SDRAM is running at 96MHz. There are -sometimes- graphics glitches which
// might be caused by the SDRAM controller latching the data when it isn't
// stable. Why is that the case with gfx data and note code ?

// P max: 4MBytes for now - some games have more than 1MiB in the PORT zone
// C max: 16MBytes for now - the NeoGeo is limited to 128MBytes, does any game use bankswitching for more ?
// S max: 1Mbytes (128kBytes is enough) - games using NEO-CMC are able to bankswitch S ROMs larger than 128kB
// System rom: 128kBytes
// SDRAM total: 0000000~1FFFFFF (32MiB)
// 0000000~01FFFFF: P1 and P2+
// 0800000~081FFFF: System ROM
// 0820000~083FFFF: S ROM
// C data is stored in the DDR3 memory

// Todo: See if it's possible to read a whole 8-pixel fix line with a n=2 burst read instead of 2x 4pixels
// Todo: Put a memcard in block RAM and allow saving/loading from HPS
// Todo: "FPGAize" LSPC and NEO-B1: Group logic and clocked always() blocks
// Todo: Have a dip-switch OSD menu
// Todo: Add minimal upd4990 test pulse logic so that MVS system ROM passes checks

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [44:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)
	input         TAPE_IN,

	// SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE
);

assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign AUDIO_S   = 1;		// Signed
assign AUDIO_MIX = status[4:3];
assign AUDIO_L = snd;
assign AUDIO_R = snd;

assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign VIDEO_ARX = 8'd10;	// 320/32
assign VIDEO_ARY = 8'd7;	// 224/32

assign VGA_DE = ~CHBL & nBNKB;

`include "build_id.v"
localparam CONF_STR1 = {
	"NEOGEO;;",
	"-;",
	"F,EP1P1,Load romset;",
	"-;",
	"O1,System type,Console,Arcade;",
	"O2,Video mode,NTSC,PAL;",
	"-;",
	"O34,Stereo mix,none,25%,50%,100%;",
	"R0,Reset & apply;",
	"J1,A,B,C,D,Start,Select;",
	"V,v",`BUILD_DATE
};


////////////////////   CLOCKS   ///////////////////

wire locked;
wire clk_sys;

// 50MHz in, 4*24=96MHz out
// CAS latency = 2 (20.8ns)
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(SDRAM_CLK),	// 180° phase shift
	.locked(locked)
);

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL = CLK_6MB;
assign nRESET = ~(ioctl_download | status[0]);

reg CLK_24M;
reg [1:0] P_BANK;
reg [2:0] counter = 0;
reg SYSTEM_MODE;

always @(negedge clk_sys)	// posedge ?
begin
	if (counter == 3'd1)
		CLK_24M <= 1'b1;
	
	if (counter == 3'd3)
	begin
		CLK_24M <= 1'b0;
		counter <= 3'd0;
	end
	else
		counter <= counter + 1'd1;
	
	if (~nRESET)
		SYSTEM_MODE <= status[1];	// Latch the system mode (AES/MVS) on reset
end

//////////////////   HPS I/O   ///////////////////

wire [15:0] joystick_0;	// xxxxxxLS DCBAUDLR
wire [15:0] joystick_1;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire [31:0] status;

wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wait;

hps_io #(.STRLEN(($size(CONF_STR1)>>3)), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR1),

	//.ps2_mouse(ps2_mouse),	// Could be used for The Irritating Maze ?

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.buttons(buttons),			// DE10 buttons ?
	.status(status),				// status read (32 bits)
	//.status_set(speed_set|arch_set|snap_hwset),	// status load on rising edge
	//.status_in({status[31:25], speed_set ? speed_req : 3'b000, status[21:13], arch_set ? arch : snap_hwset ? snap_hw : status[12:8], status[7:0]}),	// status write

	// Loading signals
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wait(ioctl_wait)
);

	// Memory info:
	// 68k RAM is in Block RAM
	// Slow VRAM is in Block RAM
	// Fast VRAM is in Block RAM
	// Palette RAM is in Block RAM
	// Line buffers are in Block RAM
	// LO ROM data is in Block RAM
	// P ROM data is in SDRAM
	// C ROM data is in DDR3 RAM
	// S ROM data is in SDRAM
	
	reg  [24:0] sdram_addr;
	
	wire [15:0] M68K_DATA;
	wire [23:1] M68K_ADDR;
	wire M68K_RW, nAS, nLDS, nUDS;
	wire [15:0] M68K_DATA_BYTE_MASK;
	wire [15:0] TG68K_DATAIN;
	wire [15:0] TG68K_DATAOUT;
	
	wire [7:0] SDD;
	wire [15:0] SDA;

	wire [23:0] PBUS;
	wire [7:0] LO_ROM_DATA;
	
	wire [19:0] C_LATCH;
	reg [3:0] C_LATCH_EXT;
	reg [63:0] CR_DOUBLE;
	
	wire [15:0] S_LATCH;
	wire [7:0] FIXD;
	
	wire [14:0] SLOW_VRAM_ADDR;
	reg [15:0] SLOW_VRAM_DATA_IN;
	wire [15:0] SLOW_VRAM_DATA_OUT;
	
	wire [10:0] FAST_VRAM_ADDR;
	wire [15:0] FAST_VRAM_DATA_IN;
	wire [15:0] FAST_VRAM_DATA_OUT;
	
	wire [11:0] PAL_RAM_ADDR;
	wire [15:0] PAL_RAM_DATA;
	reg [15:0] PAL_RAM_REG;
	
	wire [3:0] GAD;
	wire [3:0] GBD;
	wire [3:0] WE;
	wire [3:0] CK;
	
	wire [7:0] WRAML_OUT;
	wire [7:0] WRAMU_OUT;
	
	reg [1:0] SDRAM_M68K_SIG_SR;
	reg [1:0] SDRAM_CROM_SIG_SR;
	reg [1:0] SDRAM_SROM_SIG_SR;
	reg [15:0] SROM_DATA;
	reg [15:0] PROM_DATA;
	reg M68K_RD_REQ, SROM_RD_REQ;
	reg M68K_RD_RUN, SROM_RD_RUN;
	reg SDRAM_RD_PULSE;
	reg [1:0] SDRAM_READY_SR;
	
	reg CROM_READ;
	reg CROM_STATE;
	
	wire [15:0] snd;

	// SDRAM multiplexing stuff
	assign nROMOE = nROMOEL & nROMOEU;
	assign nPORTOE = nPORTOEL & nPORTOEU;
	assign SDRAM_M68K_SIG = ~&{nSROMOE, nROMOE, nPORTOE};
	
	always @(posedge clk_sys)
	begin
		if (!nRESET)
		begin
			SROM_RD_REQ <= 0;
			M68K_RD_REQ <= 0;
			SROM_RD_RUN <= 0;
			M68K_RD_RUN <= 0;
		end
		else
		begin
			// Detect rising edge of SDRAM_M68K_SIG
			SDRAM_M68K_SIG_SR <= {SDRAM_M68K_SIG_SR[0], SDRAM_M68K_SIG};
			if ((SDRAM_M68K_SIG_SR == 2'b01) & nRESET)
			begin
				if (!SROM_RD_REQ && !SROM_RD_RUN)
				begin
					// Start M68K read cycle right now
					if (sdram_ready)
					begin
						M68K_RD_RUN <= 1;
						SDRAM_RD_PULSE <= 1;
					end
				end
				else
					M68K_RD_REQ <= 1;	// Set request flag for later
			end
			
			// Detect rising edge of PCK2B
			// See dev_notes.txt about why there's only one read for FIX graphics
			// regardless of the S2H1 and S_LATCH[3] signals
			SDRAM_SROM_SIG_SR <= {SDRAM_SROM_SIG_SR[0], ~PCK2};
			if ((SDRAM_SROM_SIG_SR == 2'b01) & nRESET)
			begin
				if (!M68K_RD_REQ && !M68K_RD_RUN)
				begin
					// Start S ROM read cycle right now
					if (sdram_ready)
					begin
						SROM_RD_RUN <= 1;
						SDRAM_RD_PULSE <= 1;
					end
				end
				else
					SROM_RD_REQ <= 1;	// Set request flag for later
			end
			
			// Detect rising edge of PCK1B
			// CA4's polarity changes depending on the tile's h-flip attribute
			// Normal: CA4 high, then low
			// Flipped: CA4 low, then high
			// This is now used for DDRAM access
			SDRAM_CROM_SIG_SR <= {SDRAM_CROM_SIG_SR[0], ~PCK1};
			if ((SDRAM_CROM_SIG_SR == 2'b01) & nRESET)
			begin
				CROM_READ <= ~CROM_READ_ACK;
				CROM_STATE <= 1;
			end
			if ((CROM_READ == CROM_READ_ACK) && CROM_STATE)
			begin
				CR_DOUBLE <= crom_data;
				CROM_STATE <= 0;
			end
			
			if (SDRAM_RD_PULSE)
				SDRAM_RD_PULSE <= 0;
			
			if (sdram_ready && !SDRAM_RD_PULSE)
			begin
				if (SROM_RD_REQ && !M68K_RD_RUN)
				begin
					SROM_RD_REQ <= 0;
					SROM_RD_RUN <= 1;
					SDRAM_RD_PULSE <= 1;
				end
				else if (M68K_RD_REQ && !SROM_RD_RUN)
				begin
					M68K_RD_REQ <= 0;
					M68K_RD_RUN <= 1;
					SDRAM_RD_PULSE <= 1;
				end
			end
			
			// Terminate running reads, if needed
			SDRAM_READY_SR <= {SDRAM_READY_SR[0], sdram_ready};
			if (SDRAM_READY_SR == 2'b01)
			begin
				if (SROM_RD_RUN)
				begin
					SROM_DATA <= sdram_dout[63:48];
					SROM_RD_RUN <= 0;
				end
				if (M68K_RD_RUN)
				begin
					PROM_DATA <= {sdram_dout[55:48], sdram_dout[63:56]};
					M68K_RD_RUN <= 0;
				end
			end
		end
	end
	
	wire [63:0] sdram_dout;
	wire [15:0] sdram_din = ioctl_download ? ioctl_dout : 16'h0000;
	wire sdram_rd = ioctl_download ? 1'b0 : SDRAM_RD_PULSE;
	wire sdram_we = (ioctl_download & (ioctl_index != 8'd1) & (ioctl_index != 8'd9) & (ioctl_index < 8'd32)) ? ioctl_wr : 1'b0;
	
	wire [22:0] P2ROM_ADDR = {P_BANK + 3'd1, M68K_ADDR[19:1], 1'b0};
	wire [27:1] CROM_ADDR = {1'b0, C_LATCH_EXT, C_LATCH, 2'b00};
	
	wire [24:0] ioctl_addr_offset =
		(ioctl_index == 8'd0) ? ioctl_addr + 25'h0800000 :	// System ROM
		(ioctl_index == 8'd4) ? ioctl_addr + 25'h0000000 :	// P1 first half
		(ioctl_index == 8'd5) ? ioctl_addr + 25'h0080000 :	// P1 second half
		(ioctl_index == 8'd6) ? ioctl_addr + 25'h0100000 :	// P2
		(ioctl_index == 8'd8) ? ioctl_addr + 25'h0820000 :	// S1
		25'h0000000;
	
	// sdram_addr is 25 bits, LSB is = 0 in word mode
	always_comb begin 
		casez ({ioctl_download, SROM_RD_RUN, ~nROMOE & M68K_RD_RUN, ~nPORTOE & M68K_RD_RUN, ~nSROMOE & M68K_RD_RUN})
			// Loading pass-through
			5'b1zzzz: sdram_addr = ioctl_addr_offset;
			// S ROM Bytes $0820000~$083FFFF
			5'b01zzz: sdram_addr = {8'b0_1000_001, S_LATCH[15:4], S_LATCH[2:0], ~S_LATCH[3], 1'b0};
			// P1 ROM $0000000~$0100000
			5'b001zz: sdram_addr = {5'b0_0000, M68K_ADDR[19:1], 1'b0};
			// P2 ROM $0100000~$04FFFFF bankswitched
			5'b0001z: sdram_addr = {2'b0_0, P2ROM_ADDR};
			// System ROM $0800000~$081FFFF
			5'b00001: sdram_addr = {8'b0_1000_000, M68K_ADDR[16:1], 1'b0};
			5'b00000: sdram_addr = 25'h0000000;
		endcase
	end
	
	sdram ram
	(
		.*,					// Connect all nets with the same names (SDRAM_* pins)
		.init(~locked),	// Init SDRAM as soon as the PLL is locked
		.clk(clk_sys),
		.dout(sdram_dout),
		.din(sdram_din),
		.addr(sdram_addr),
		.wtbt(2'b11),		// Always used in 16-bit mode
		.we(sdram_we),
		.rd(sdram_rd),
		.ready_first(sdram_ready),
		.ready_fourth(ready_fourth)
	);
	
	assign DDRAM_CLK = clk_sys;
	wire [27:0] ioctl_addr_crom = {ioctl_addr, 1'b0} + {ioctl_index[4:1], 18'h00000, ioctl_index[0], 1'b0};
	
	reg  crom_wr;
	wire crom_wrack;
	wire [63:0] crom_data;
	
	ddram ddram
	(
		.*,

		.wraddr(ioctl_addr_crom),
		.din(ioctl_dout),
		.we_req(crom_wr),
		.we_ack(crom_wrack),

		.rdaddr(CROM_ADDR),
		.dout(crom_data),
		.rd_req(CROM_READ),
		.rd_ack(CROM_READ_ACK)
	);
	
	always @(posedge clk_sys) begin
		reg old_download, old_reset;
		old_download <= ioctl_download;
		old_reset <= RESET;

		if(~old_reset && RESET) ioctl_wait <= 0;
		if(~old_download && ioctl_download) crom_wr <= 0;
		else begin
			if(ioctl_wr && (ioctl_index >= 8'd32)) begin
				ioctl_wait <= 1;
				crom_wr <= ~crom_wr;
			end else if(ioctl_wait && (crom_wr == crom_wrack)) begin
				ioctl_wait <= 0;
			end
		end
	end

	
	neo_d0 D0(CLK_24M, nRESET, nRESETP, CLK_12M, CLK_68KCLK, CLK_68KCLKB, CLK_6MB, CLK_1HB, M68K_ADDR[4],
				nBITWD0, M68K_DATA[5:0], SDA[15:11], SDA[4:2], nSDRD, nSDWR, nMREQ, nIORQ, nZ80NMI, nSDW, nSDZ80R,
				nSDZ80W, nSDZ80CLR, nSDROM, nSDMRD, nSDMWR, SDRD0, SDRD1, n2610CS, n2610RD, n2610WR, nZRAMCS,
				BNK, , );
	
	cpu_68k	M68KCPU(CLK_68KCLK, nRESET, IPL1, IPL0, nDTACK, M68K_ADDR,
		TG68K_DATAIN, TG68K_DATAOUT, nLDS, nUDS, nAS, M68K_RW);
	
	// TG68K doesn't like byte masking with Z's, replace with 0's:
	assign M68K_DATA_BYTE_MASK = (~|{nLDS, nUDS}) ? M68K_DATA :
											(~nLDS) ? {8'h00, M68K_DATA[7:0]} :
											(~nUDS) ? {M68K_DATA[15:8], 8'h00} :
											16'h0000;

	assign M68K_DATA = M68K_RW ? 16'bzzzzzzzzzzzzzzzz : TG68K_DATAOUT;
	assign TG68K_DATAIN = M68K_RW ? M68K_DATA_BYTE_MASK : 16'h0000;
	
	// Bankswitching for the PORT zone, do all games use a 1MB window ?
	always @(posedge nPORTWEL or negedge nRESET)
	begin
		if (!nRESET)
			P_BANK <= 2'd0;
		else
			P_BANK <= M68K_DATA[1:0];
	end
	
	assign FIXD = S2H1 ? SROM_DATA[15:8] : SROM_DATA[7:0];
	
	assign M68K_DATA = (nROMOE & nSROMOE & nPORTOE) ? 16'bzzzzzzzzzzzzzzzz : {PROM_DATA[7:0], PROM_DATA[15:8]};
	
	m68k_ram WRAML(M68K_ADDR[15:1], CLK_24M, M68K_DATA[7:0], ~nWWL, WRAML_OUT);
	m68k_ram WRAMU(M68K_ADDR[15:1], CLK_24M, M68K_DATA[15:8], ~nWWU, WRAMU_OUT);
	assign M68K_DATA[7:0] = nWRL ? 8'bzzzzzzzz : WRAML_OUT;
	assign M68K_DATA[15:8] = nWRU ? 8'bzzzzzzzz : WRAMU_OUT;
	
	// Todo: verify
	assign nBITWD0 = |{nBITW0, M68K_ADDR[6:5]};
	
	syslatch SL(M68K_ADDR[4:1], nBITW1, nRESET, SHADOW, nVEC, nCARDWEN, CARDWENB, nREGEN, nSYSTEM, nSRAMWEN, PALBNK);

	neo_e0 E0(M68K_ADDR[23:1], 3'b000, nSROMOEU, nSROMOEL, nSROMOE, nVEC, A23Z, A22Z, );
	
	neo_c1 C1(M68K_ADDR[21:17], M68K_DATA[15:8], A22Z, A23Z, nLDS, nUDS, M68K_RW, nAS, nROMOEL, nROMOEU,
				nPORTOEL, nPORTOEU, nPORTWEL, nPORTWEU, nPORTADRS, nWRL, nWRU, nWWL, nWWU, nSROMOEL, nSROMOEU, 
				nSRAMOEL, nSRAMOEU, nSRAMWEL, nSRAMWEU, nLSPOE, nLSPWE, nCRDO, nCRDW, nCRDC, nSDW,
				~{joystick_0[9:4], joystick_0[0], joystick_0[1], joystick_0[2], joystick_0[3]},
				~{joystick_1[9:4], joystick_1[0], joystick_1[1], joystick_1[2], joystick_1[3]},
				1'b1, 1'b1, 1'b1,	// nCD1, nCD2, nWP,
				1'b1, 1'b1, 1'b1, 1'b1,	// nROMWAIT, nPWAIT0, nPWAIT1, PDTACK,
				SDD, nSDZ80R, nSDZ80W, nSDZ80CLR, CLK_68KCLK,
				nDTACK, nBITW0, nBITW1, nDIPRD0, nDIPRD1, nPAL, SYSTEM_MODE);
	
	neo_273	NEO273(PBUS[19:0], ~PCK1, ~PCK2, C_LATCH, S_LATCH);
	// 4 MSBs not handled by NEO-273
	always @(negedge PCK1)
		C_LATCH_EXT <= PBUS[23:20];

	// This is used to split burst-read sprite gfx data in half at the right time
	reg [2:0] LOAD_SR;
	reg CA4_REG;
	
	always @(posedge clk_sys)
	begin
		LOAD_SR <= {LOAD_SR[1:0], LOAD};
		if (LOAD_SR == 3'b011)
			CA4_REG <= CA4;
	end
	
	wire [31:0] CR = CA4_REG ? CR_DOUBLE[31:0] : CR_DOUBLE[63:32];
	
	neo_zmc2 ZMC2(CLK_12M, EVEN1, LOAD, H, CR, GAD, GBD, DOTA, DOTB);
	
	// VCS is normally used as the LO ROM's nOE but the NeoGeo relies on the fact that the LO ROM
	// will have its output still active for a short moment (~50ns) after nOE goes high
	// nPBUS_OUT_EN is used internally by LSPC2 but it's broken out here to use the additional
	// half mclk cycle it provides compared to VCS. This makes sure LO_ROM_DATA is valid when latched.
	wire lo_loading = ioctl_download & (ioctl_index == 8'd1);
	wire [15:0] LO_ADDR = lo_loading ? ioctl_addr[16:1] : PBUS[15:0];
	wire lo_we = lo_loading ? ioctl_wr : 1'b0;
	lo_rom LO(LO_ADDR, clk_sys, ioctl_dout[7:0], lo_we, LO_ROM_DATA);	// CLK_24M
	assign PBUS[23:16] = nPBUS_OUT_EN ? LO_ROM_DATA : 8'bzzzzzzzz;
	
	fast_vram UFV(
		FAST_VRAM_ADDR,
		~CLK_24M,		// Is just CLK ok ?
		FAST_VRAM_DATA_OUT,
		~CWE,
		FAST_VRAM_DATA_IN);
		
	slow_vram USV(
		SLOW_VRAM_ADDR,
		~CLK_24M,		// Is just CLK ok ?
		SLOW_VRAM_DATA_OUT,
		~BWE,
		SLOW_VRAM_DATA_IN);
	
	// Cartridge PCB
	//assign SPR_ROM_ADDR = {C_LATCH[19:4], CA4, C_LATCH[3:0]};
	//assign FIX_ROM_ADDR = {S_LATCH[15:3], S2H1, S_LATCH[2:0]};
	
	wire [21:11] MA;
	wire [7:0] M1_ROM_DATA;
	wire [7:0] Z80_RAM_DATA;
	
	zmc ZMC(SDRD0, SDA[1:0], SDA[15:8], MA);
	
	wire m1_loading = ioctl_download & (ioctl_index == 8'd9);
	wire [16:0] M1_ADDR = m1_loading ? ioctl_addr[17:1] : {MA[16:11], SDA[10:0]};
	wire m1_we = m1_loading ? ioctl_wr : 1'b0;
	z80_rom M1(M1_ADDR, clk_sys, ioctl_dout[7:0], m1_we, M1_ROM_DATA);
	
	z80_ram Z80RAM(SDA[10:0], CLK_4M, SDD, ~(nZRAMCS | nSDMWR), Z80_RAM_DATA);		
	
	assign SDD = (~SDRD0 | ~SDRD1) ? 8'b00000000 :	// Fix to prevent TV80 from going nuts because the data bus is open on port reads for NEO-ZMC
						(~nSDROM & ~nSDMRD) ? M1_ROM_DATA : 
						(~nZRAMCS & ~nSDMRD) ? Z80_RAM_DATA :
						(~n2610CS & ~n2610RD) ? YM2610_DOUT :
						8'bzzzzzzzz;
	
	cpu_z80 Z80CPU(CLK_4M, nRESET, SDD, SDA, nIORQ, nMREQ, nSDRD, nSDWR, nZ80INT, nZ80NMI);
	
	wire [7:0] YM2610_DOUT;
	jt03 YM2610(nRESET, CLK_8M, 1'b1, SDD, SDA[0], n2610CS, n2610WR, YM2610_DOUT, nZ80INT,
						, , , , , snd, );

	lspc2_a2	LSPC(CLK_24M, nRESET,
					PBUS[15:0],
					PBUS[23:16],
					M68K_ADDR[3:1],
					M68K_DATA,
					nLSPOE, nLSPWE,
					DOTA, DOTB,
					CA4, S2H1, S1H1,
					LOAD,
					H, EVEN1, EVEN2,
					IPL0, IPL1,
					CHG, LD1, LD2,
					PCK1, PCK2,
					WE, CK, SS1, SS2,
					nRESETP,
					VGA_HS, VGA_VS,
					CHBL, nBNKB,
					VCS,
					CLK_8M,	CLK_4M,
					SLOW_VRAM_ADDR, SLOW_VRAM_DATA_IN, SLOW_VRAM_DATA_OUT, BOE, BWE,
					FAST_VRAM_ADDR, FAST_VRAM_DATA_IN, FAST_VRAM_DATA_OUT, CWE,
					nPBUS_OUT_EN,
					status[2]
					);
	
	neo_b1	B1(CLK_24M, CLK_6MB, CLK_1HB,
					PBUS,
					FIXD,
					PCK1, PCK2,
					CHBL, nBNKB,
					GAD, GBD,
					WE,
					CK,
					CHG, LD1, LD2, SS1, SS2, S1H1, A23Z, A22Z,
					PAL_RAM_ADDR, nLDS, M68K_RW, nAS, M68K_ADDR[21:17], M68K_ADDR[12:1],
					, , 1'b1);

	pal_ram PALRAM({PALBNK, PAL_RAM_ADDR}, CLK_12M, M68K_DATA, (~nPAL & ~M68K_RW), PAL_RAM_DATA);
	
	// DAC latches
	always @(posedge CLK_6MB, negedge nBNKB)
	begin
		if (!nBNKB)
			PAL_RAM_REG <= 16'h0000;
		else
			PAL_RAM_REG <= PAL_RAM_DATA;
	end

	// Final video output 6 bits -> 8 bits
	assign VGA_R = {PAL_RAM_REG[11:8], PAL_RAM_REG[14], PAL_RAM_REG[15], 2'b00};
	assign VGA_G = {PAL_RAM_REG[7:4], PAL_RAM_REG[13], PAL_RAM_REG[15], 2'b00};
	assign VGA_B = {PAL_RAM_REG[3:0], PAL_RAM_REG[12], PAL_RAM_REG[15], 2'b00};
	
	// VGA DAC tester
	/*reg [23:0] TEMP;
	reg [1:0] TEST_COLOR;
	always @(posedge CLK_24M)
	begin
		TEMP <= TEMP + 1'b1;
		if (TEMP >= 24'd12000000)
		begin
			TEMP <= 24'd0;
			TEST_COLOR <= TEST_COLOR + 1'b1;
		end
	end
	
	assign VGA_R = (TEST_COLOR == 2'd0) ? 8'hFF : 8'h00;
	assign VGA_G = (TEST_COLOR == 2'd1) ? 8'hFF : 8'h00;
	assign VGA_B = (TEST_COLOR == 2'd2) ? 8'hFF : 8'h00;*/

endmodule
