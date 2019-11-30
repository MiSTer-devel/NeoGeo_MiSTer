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

// Current status:
// ADPCM kinda works, many loud glitches. DDR3 latency issue ? Signal are ready in Signaltap
// Neo CD CD check ok but crashes when loading. No more video glitches.

// How about not using a cache at all and DMAing directly from the data fed by the HPS ?
// The "sector ready" IRQ could be triggered just when a sector is requested, and the actual transfer
// could be done when the system ROM starts up the DMA transfer ?

// Neo CD times 12/05/2019:
// SECTOR_READY goes high at SECTOR_TIMER == 430631
// So it takes 600000-430631=169369 ticks to get a sector from HPS
// 169369/120M=1.41ms (1451 kB/s)
// DMA copy: 215 ticks for 10 bytes
// So 215/120M/10=179.17ns per byte (5450 kB/s)

// Neo CD times 11/05/2019:
// DMA copy: 616 ticks for 10 bytes
// So 215/120M/10=513.3ns per byte (1902 kB/s)

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

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
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output  [1:0] VGA_SL,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
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
	output        SDRAM_nWE,

	output        SDRAM2_CLK,
`ifdef DUAL_SDRAM
	//
	// Secondary SDRAM notes:
	// SDRAM2_EN: 
	//
	//    1 - MiSTer is configured for SDRAM2 use, core can use SDRAM2_* signals.
	//        It doesn't mean SDRAM module is plugged.
	//
	//    0 - MiSter is not configured for SDRAM2 module, the core
	//        has to set all output SDRAM2_* signals to Z ASAP to avoid signal collision!
	//
	// {DQMH,DQML} are mapped to A[12:11]
	// You need to set A[12:11] appropriately in READ/WRITE commands for correct operations.
	// in ACTIVATE command the whole A[12:0] can be used as it doesn't affect the input/output of data.
	// CKE is hardwired to 1 on the module.
	//
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
	input         SDRAM2_EN, 
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign AUDIO_S   = 1;		// Signed
assign AUDIO_MIX = status[5:4];
assign AUDIO_L = snd_left;
assign AUDIO_R = snd_right;

assign LED_USER  = status[0] | bk_pending;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = osd_btn;

assign VIDEO_ARX = status[17] ? 8'd16 : 8'd10;	// 320/32
assign VIDEO_ARY = status[17] ? 8'd9  : 8'd7;	// 224/32

// status bit definition:
// 31       23       15       7
// --AA-PSS -------- L--CGGDD DEEMVTTR
//  :	status[0]		System Reset, used by the HPS, keep it there
// T:	status[2:1]		System type, 0=Console, 1=Arcade, 2=CD, 3=CDZ
// V:	status[3]		Video mode
// M:	status[4]		Memory card presence
// E:	status[6:5]		Stereo mix
// D:	status[9:7]		DIP switches
// G:	status[11:10]	Neo CD region
// C:	status[12]		Save memory card & backup RAM
// L:	status[12]		CD lid state (DEBUG)
//  :	status[13]		Primary SDRAM size 32MB/64MB
//  :	status[14]		Manual Reset
//  :	status[20:15]  OSD options
// 0123456789 ABCDEFGHIJKLMNO

// Conditional modification of the CONF strings chaining according to chosen system type
// Con Arc CD CDz
// 00  01  10 11
// F   F   +  +  ~SYSTEM_CDx;
// +   +   S  S  SYSTEM_CDx; 
// O   O   +  +  ~SYSTEM_CDx;
// +   O   +  +  SYSTEM_MVS; 
// +   +   O  O  SYSTEM_CDx;   

`include "build_id.v"
localparam CONF_STR = {
	"NEOGEO;;",
	"-;",
	"H0FS1,*,Load ROM set;",
	"H1S1,ISOBIN,Load CD Image;",
	"-;",
	"H3OP,FM,ON,OFF;",
	"H3OQ,ADPCMA,ON,OFF;",
	"H3OR,ADPCMB,ON,OFF;",
	"H3OS,PSG,ON,OFF;",
	"H3oP,ADPCMA CH 1,ON,OFF;",
	"H3oQ,ADPCMA CH 2,ON,OFF;",
	"H3oR,ADPCMA CH 3,ON,OFF;",
	"H3oS,ADPCMA CH 4,ON,OFF;",
	"H3oT,ADPCMA CH 5,ON,OFF;",
	"H3oU,ADPCMA CH 6,ON,OFF;",
	"H3-;",
	"O12,System Type,Console(AES),Arcade(MVS);", //,CD,CDZ;",
	"OM,BIOS,UniBIOS,Original;",
	"O3,Video Mode,NTSC,PAL;",
	"-;",
	"H0O4,Memory Card,Plugged,Unplugged;",
	"RL,Reload Memory Card;",
	"D4RC,Save Memory Card;",
	"OO,Autosave,OFF,ON;",
	"H1-;",
	"H1OAB,Region,US,EU,JP,AS;",
	"H1OF,CD lid,Opened,Closed;",
	"H2-;",
	"H2O7,[DIP] Settings,OFF,ON;",
	"H2O8,[DIP] Freeplay,OFF,ON;",
	"H2O9,[DIP] Freeze,OFF,ON;",
	"-;",
	"OG,Width,320px,304px;",
	"OH,Aspect Ratio,Original,Wide;",
	"OIK,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"O56,Stereo Mix,none,25%,50%,100%;",
	"-;",
	"RE,Reset & apply;",  // decouple manual reset from system reset 
	"J1,A,B,C,D,Start,Select,Coin,ABC;",	// ABC is a special key to press A+B+C at once, useful for
	"V,v",`BUILD_DATE								// keyboards that don't allow more than 2 keypresses at once
};


////////////////////   CLOCKS   ///////////////////

wire locked;
wire clk_sys;
wire CLK_24M = counter_p[1];

// 50MHz in, 4*24=96MHz out
// CAS latency = 2 (20.8ns)
pll pll(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(SDRAM_CLK),	// Phase shifted
	.outclk_2(SDRAM2_CLK),	// Phase shifted
	.outclk_3(CLK_VIDEO),
	.locked(locked)
);

// The watchdog should output nRESET but it makes video sync stop for a moment, so the
// MiSTer OSD jumps around. Provide an indication for devs that a watchdog reset happened ?

reg [14:0] TRASH_ADDR;
reg  [1:0] SYSTEM_TYPE;

reg nRESET;
always @(posedge CLK_24M) begin
	nRESET <= &TRASH_ADDR;
	if (~&TRASH_ADDR) TRASH_ADDR <= TRASH_ADDR + 1'b1;
	if (ioctl_download | status[0] | status[14] | buttons[1] | bk_loading | RESET) begin
		TRASH_ADDR <= 0;
		SYSTEM_TYPE <= status[2:1];	// Latch the system type on reset
	end
end

reg [1:0] counter_p = 0;
always @(posedge clk_sys) counter_p <= counter_p + 1'd1;

reg osd_btn = 0;
always @(posedge CLK_24M) begin
	integer timeout = 0;
	
	if(!RESET) begin
		osd_btn <= 0;
		if(timeout < 24000000) begin
			timeout <= timeout + 1;
			osd_btn <= 1;
		end
	end
end

//////////////////   HPS I/O   ///////////////////

// VD 0: Save file
// VD 1: CD bin file
// VD 2: CD cue file, let MiSTer binary take care of it, do not touch !
wire [1:0] img_mounted;
wire [1:0] sd_rd;
wire [1:0] sd_wr;
assign sd_rd[0] = bk_rd;
assign sd_wr[0] = bk_wr;
assign sd_wr[1] = 0;

wire sd_ack, sd_buff_wr, img_readonly;

wire  [7:0] sd_buff_addr;	// Address inside 256-word sector
wire [15:0] sd_buff_dout;
wire [15:0] sd_buff_din;
wire [15:0] sd_req_type;
wire [63:0] img_size;
reg  [31:0] sd_lba;
wire [31:0] CD_sd_lba;

wire [15:0] joystick_0;	// ----HNLS DCBAUDLR
wire [15:0] joystick_1;
wire  [1:0] buttons;
wire [10:0] ps2_key;
wire        forced_scandoubler;
wire [63:0] status;

wire [64:0] rtc;

wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire        ioctl_download;
wire  [7:0] ioctl_index;

wire SYSTEM_MVS = (SYSTEM_TYPE == 2'd1);
wire SYSTEM_CDx = SYSTEM_TYPE[1];

wire [15:0] sdram_sz;
wire [21:0] gamma_bus;

hps_io #(.STRLEN($size(CONF_STR)>>3), .WIDE(1), .VDNUM(2)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),
	.forced_scandoubler(forced_scandoubler),

	.joystick_0(joystick_0), .joystick_1(joystick_1),
	.buttons(buttons),
	.ps2_key(ps2_key),

	.status(status),				// status read (32 bits)
	.status_menumask({status[22], 10'd0, bk_autosave | ~bk_pending, ~dbg_menu,~SYSTEM_MVS,~SYSTEM_CDx,SYSTEM_CDx}),

	.RTC(rtc),
	.sdram_sz(sdram_sz),
	.gamma_bus(gamma_bus),

	// Loading signals
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wait(ddram_wait | memcp_wait),
	
	.sd_lba(sd_req_type ? CD_sd_lba : sd_lba),
	.sd_rd(sd_rd), .sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.sd_req_type(sd_req_type),
	
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size)
);

reg dbg_menu = 0;
always @(posedge clk_sys) begin
	reg old_stb;
	reg enter = 0;
	reg esc = 0;
	
	old_stb <= ps2_key[10];
	if(old_stb ^ ps2_key[10]) begin
		if(ps2_key[7:0] == 'h5A) enter <= ps2_key[9];
		if(ps2_key[7:0] == 'h76) esc   <= ps2_key[9];
	end
	
	if(enter & esc) begin
		dbg_menu <= ~dbg_menu;
		enter <= 0;
		esc <= 0;
	end
end

//////////////////   Her Majesty   ///////////////////

	reg  [31:0] cfg = 0;
	wire [15:0] snd_right;
	wire [15:0] snd_left;

	wire nRESETP, nSYSTEM, CARD_WE, SHADOW, nVEC, nREGEN, nSRAMWEN, PALBNK;
	wire CD_nRESET_Z80;
	
	// Clocks
	wire CLK_12M, CLK_68KCLK, CLK_68KCLKB, CLK_8M, CLK_6MB, CLK_4M, CLK_4MB, CLK_1HB;
	
	// 68k stuff
	wire [15:0] M68K_DATA;
	wire [23:1] M68K_ADDR;
	wire A22Z, A23Z;
	wire M68K_RW, nAS, nLDS, nUDS, nDTACK, nHALT, nBR, nBG, nBGACK;
	wire [15:0] M68K_DATA_BYTE_MASK;
	wire [15:0] FX68K_DATAIN;
	wire [15:0] FX68K_DATAOUT;
	wire IPL0, IPL1;
	wire FC0, FC1, FC2;
	reg [3:0] P_BANK;
	
	// RTC stuff
	wire RTC_DOUT, RTC_DIN, RTC_CLK, RTC_STROBE, RTC_TP;
	
	// OEs and WEs
	wire nSROMOEL, nSROMOEU, nSROMOE;
	wire nROMOEL, nROMOEU;
	wire nPORTOEL, nPORTOEU, nPORTWEL, nPORTWEU, nPORTADRS;
	wire nSRAMOEL, nSRAMOEU, nSRAMWEL, nSRAMWEU;
	wire nWRL, nWRU, nWWL, nWWU;
	wire nLSPOE, nLSPWE;
	wire nPAL, nPAL_WE;
	wire nBITW0, nBITW1, nBITWD0, nDIPRD0, nDIPRD1;
	wire nSDROE, nSDPOE;
	
	// RAM outputs
	wire [7:0] WRAML_OUT;
	wire [7:0] WRAMU_OUT;
	wire [15:0] SRAM_OUT;
	
	// Memory card stuff
	wire [23:0] CDA;
	wire [2:0] BNK;
	wire [7:0] CDD;
	wire nCD1, nCD2;
	wire nCRDO, nCRDW, nCRDC;
	wire nCARDWEN, CARDWENB;
	
	// Z80 stuff
	wire [7:0] SDD_IN;
	wire [7:0] SDD_OUT;
	wire [7:0] SDD_RD_C1;
	wire [15:0] SDA;
	wire nSDRD, nSDWR, nMREQ, nIORQ;
	wire nZ80INT, nZ80NMI, nSDW, nSDZ80R, nSDZ80W, nSDZ80CLR;
	wire nSDROM, nSDMRD, nSDMWR, SDRD0, SDRD1, nZRAMCS;
	wire n2610CS, n2610RD, n2610WR;
	
	// Graphics stuff
	wire [23:0] PBUS;
	wire [7:0] LO_ROM_DATA;
	wire nPBUS_OUT_EN;
	
	wire [19:0] C_LATCH;
	reg   [3:0] C_LATCH_EXT;
	wire [63:0] CR_DOUBLE;
	wire [26:0] CROM_ADDR;
	
	wire [1:0] FIX_BANK;
	wire [15:0] S_LATCH;
	wire [7:0] FIXD;
	wire [10:0] FIXMAP_ADDR;
	
	wire CWE, BWE, BOE;
	
	wire [14:0] SLOW_VRAM_ADDR;
	reg [15:0] SLOW_VRAM_DATA_IN;
	wire [15:0] SLOW_VRAM_DATA_OUT;
	
	wire [10:0] FAST_VRAM_ADDR;
	wire [15:0] FAST_VRAM_DATA_IN;
	wire [15:0] FAST_VRAM_DATA_OUT;
	
	wire [11:0] PAL_RAM_ADDR;
	wire [15:0] PAL_RAM_DATA;
	reg [15:0] PAL_RAM_REG;
	
	wire PCK1, PCK2, EVEN1, EVEN2, LOAD, H;
	wire DOTA, DOTB;
	wire CA4, S1H1, S2H1;
	wire CHBL, nBNKB, VCS;
	wire CHG, LD1, LD2, SS1, SS2;
	wire [3:0] GAD;
	wire [3:0] GBD;
	wire [3:0] WE;
	wire [3:0] CK;
	
	wire CD_VIDEO_EN, CD_FIX_EN, CD_SPR_EN;
	
	// SDRAM multiplexing stuff
	wire [15:0] SROM_DATA;
	wire [15:0] PROM_DATA;

	parameter INDEX_SPROM = 0;
	parameter INDEX_LOROM = 1;
	parameter INDEX_SFIXROM = 2;
	parameter INDEX_P1ROM_A = 4;
	parameter INDEX_P1ROM_B = 5;
	parameter INDEX_P2ROM = 6;
	parameter INDEX_S1ROM = 8;
	parameter INDEX_M1ROM = 9;
	parameter INDEX_MEMCP = 10;
	parameter INDEX_CROM0 = 15;
	parameter INDEX_VROMS = 16;
	parameter INDEX_CROMS = 64;
	
	wire video_mode = status[3];

	wire [3:0] cart_pchip = cfg[22:20];
	wire       use_pcm    = cfg[23];
	wire [1:0] cart_chip  = cfg[25:24]; // legacy option: 0 - none, 1 - PRO-CT0, 2 - Link MCU
	wire [1:0] cmc_chip   = cfg[27:26]; // type 1/2

	// Memory card and backup ram image save/load
	wire downloading = status[0];
	reg bk_rd, bk_wr;
	reg bk_ena = 0;
	reg bk_pending = 0;

	wire bk_autosave = status[24];
	// Memory write flag for backup memory & memory card
	// (~nBWL | ~nBWU) : [AES] Unibios (set to MVS) softdip settings, [MVS] cab settings, dates, timer, high scores, saves, & bookkeeeping
	// CARD_WE         : [AES/MVS] game saves and high scores
	wire bk_change = ~nBWL | ~nBWU | CARD_WE;
	wire memcard_change;

	always @(posedge clk_sys) begin
		reg old_downloading = 0;

		old_downloading <= downloading;
		if(~old_downloading & downloading) bk_ena <= 0;

		// Save file always mounted in the end of downloading state.
		if(downloading && img_mounted[0] && !img_readonly) bk_ena <= 1;

		// Determine whether file needs to be written
		if (bk_change)     bk_pending <= 1;
		else if (bk_state) bk_pending <= 0;
	end

	wire bk_load    = status[21];
	wire bk_save    = status[12] | (bk_autosave & OSD_STATUS);
	reg  bk_loading = 0;
	reg  bk_state   = 0;

	always @(posedge clk_sys) begin
		reg old_downloading = 0;
		reg old_load = 0, old_save = 0, old_ack;

		old_downloading <= downloading;

		old_load <= bk_load;
		old_save <= bk_save;
		old_ack  <= sd_ack;

		if(~old_ack & sd_ack) {bk_rd, bk_wr} <= 0;

		if(!bk_state) begin
			if(bk_ena & ((~old_load & bk_load) | (~old_save & bk_save & bk_pending))) begin
				bk_state <= 1;
				bk_loading <= bk_load;
				sd_lba <= 0;
				bk_rd  <=  bk_load;
				bk_wr  <= ~bk_load;
			end
			// always load backup so it will erase the memory if doesn't exist
			if(old_downloading & ~downloading & bk_ena) begin
				bk_state <= 1;
				bk_loading <= 1;
				sd_lba <= 0;
				bk_rd  <= 1;
				bk_wr  <= 0;
			end
		end else begin
			if(old_ack & ~sd_ack) begin
				if (sd_lba >= 'h8F) begin // 64KB + 8KB regardless the selected system
					bk_loading <= 0;
					bk_state <= 0;
				end else begin
					sd_lba <= sd_lba + 1'd1;
					bk_rd  <=  bk_loading;
					bk_wr  <= ~bk_loading;
				end
			end
		end
	end

	wire [1:0] CD_REGION;
	always @(status[11:10])
	begin
		// CD Region code remap:
		// status[11:10] remap
		// 00            10 US
		// 01            01 EU
		// 10            11 JP
		// 11            00 ASIA
		case(status[11:10])
			 2'b00: CD_REGION = 2'b10;
			 2'b01: CD_REGION = 2'b01;
			 2'b10: CD_REGION = 2'b11;
			 2'b11: CD_REGION = 2'b00;
		endcase
	end
	
	wire [2:0] CD_TR_AREA;	// Transfer area code
	wire [15:0] CD_TR_WR_DATA;
	wire [19:1] CD_TR_WR_ADDR;
	wire [1:0] CD_BANK_SPR;
	
	wire CD_TR_WR_SPR, CD_TR_WR_PCM, CD_TR_WR_Z80, CD_TR_WR_FIX;
	wire CD_BANK_PCM;
	wire CD_IRQ;
	wire DMA_RUNNING, DMA_WR_OUT, DMA_RD_OUT;
	wire [15:0] DMA_DATA_OUT;
	wire [23:0] DMA_ADDR_IN;
	wire [23:0] DMA_ADDR_OUT;
	
	wire DMA_SDRAM_BUSY;
	wire PROM_DATA_READY;

	cd_sys cdsystem(
		.nRESET(nRESET),
		.clk_sys(clk_sys), .CLK_68KCLK(CLK_68KCLK),
		.M68K_ADDR(M68K_ADDR), .M68K_DATA(M68K_DATA), .A22Z(A22Z), .A23Z(A23Z),
		.nLDS(nLDS), .nUDS(nUDS), .M68K_RW(M68K_RW), .nAS(nAS), .nDTACK(nDTACK_ADJ),
		.nBR(nBR), .nBG(nBG), .nBGACK(nBGACK),
		.SYSTEM_TYPE(SYSTEM_TYPE),
		.CD_REGION(CD_REGION),
		.CD_LID(status[15]),	// CD lid state (DEBUG)
		.CD_VIDEO_EN(CD_VIDEO_EN), .CD_FIX_EN(CD_FIX_EN), .CD_SPR_EN(CD_SPR_EN),
		.CD_nRESET_Z80(CD_nRESET_Z80),
		.CD_TR_WR_SPR(CD_TR_WR_SPR), .CD_TR_WR_PCM(CD_TR_WR_PCM),
		.CD_TR_WR_Z80(CD_TR_WR_Z80), .CD_TR_WR_FIX(CD_TR_WR_FIX),
		.CD_TR_AREA(CD_TR_AREA),
		.CD_BANK_SPR(CD_BANK_SPR), .CD_BANK_PCM(CD_BANK_PCM),
		.CD_TR_WR_DATA(CD_TR_WR_DATA), .CD_TR_WR_ADDR(CD_TR_WR_ADDR),
		.CD_IRQ(CD_IRQ), .IACK(IACK),
		.sd_req_type(sd_req_type),
		.sd_rd(sd_rd[1]), .sd_ack(sd_ack), .sd_buff_wr(sd_buff_wr),
		.sd_buff_dout(sd_buff_dout), .sd_lba(CD_sd_lba),
		.DMA_RUNNING(DMA_RUNNING),
		.DMA_DATA_IN(PROM_DATA), .DMA_DATA_OUT(DMA_DATA_OUT),
		.DMA_WR_OUT(DMA_WR_OUT), .DMA_RD_OUT(DMA_RD_OUT),
		.DMA_ADDR_IN(DMA_ADDR_IN),		// Used for reading
		.DMA_ADDR_OUT(DMA_ADDR_OUT),	// Used for writing
		.DMA_SDRAM_BUSY(DMA_SDRAM_BUSY)
	);
	
	// The P1 zone is writable on the Neo CD
	// Is there a write enable register for it ?
	wire CD_EXT_WR = DMA_RUNNING ? (SYSTEM_CDx & (DMA_ADDR_OUT[23:21] == 3'd0) & DMA_WR_OUT) :	// DMA writes to $000000~$1FFFFF
							(SYSTEM_CDx & ~|{A23Z, A22Z, M68K_ADDR[21]} & ~M68K_RW & ~nAS);				// CPU writes to $000000~$1FFFFF
	
	wire CD_WR_SDRAM_SIG = SYSTEM_CDx & |{CD_TR_WR_SPR, CD_TR_WR_FIX, CD_EXT_WR};
	
	wire nROMOE = nROMOEL & nROMOEU;
	wire nPORTOE = nPORTOEL & nPORTOEU;
	
	// CD system work ram is in SDRAM
	wire CD_EXT_RD = DMA_RUNNING ? (SYSTEM_CDx & (DMA_ADDR_IN[23:21] == 3'd0) & DMA_RD_OUT) :		// DMA reads from $000000~$1FFFFF
											(SYSTEM_CDx & (~nWRL | ~nWRU));											// CPU reads from $100000~$1FFFFF
	
	wire        sdram_ready;
	wire [26:1] sdram_addr;
	wire [63:0] sdram_dout;
	wire [15:0] sdram_din;
	
	// ioctl_download is used to load the system ROM on CD systems, we need it !
	wire ioctl_en = SYSTEM_CDx ? (ioctl_index == INDEX_SPROM) :
						(ioctl_index != INDEX_LOROM && ioctl_index != INDEX_M1ROM && ioctl_index != INDEX_MEMCP && (ioctl_index < INDEX_VROMS || ioctl_index >= INDEX_CROMS));
	
	wire [26:0] CROM_LOAD_ADDR = ({ioctl_addr[25:0], 1'b0} + {ioctl_index[7:1]-INDEX_CROMS[7:1], 18'h00000, ioctl_index[0], 1'b0});
	wire [26:0] VROM_LOAD_ADDR = ({1'b0, ioctl_addr[25:0]} + {ioctl_index[7:0]-INDEX_VROMS[7:0], 19'h00000});

	localparam SPROM_OFFSET   = 27'h0000000; // System ROM: $0000000~$007FFFF
	localparam SFIXROM_OFFSET = 27'h0020000; // SFIX:       $0020000~$003FFFF (in sys ROM)
	localparam S1ROM_OFFSET   = 27'h0080000; // S1:         $0080000~$00FFFFF
	localparam P1ROM_A_OFFSET = 27'h0200000; // P1+:        $0200000~...
	localparam P1ROM_B_OFFSET = 27'h0280000; // P1:         $0280000~$02FFFFF (secondary 512KB)
	localparam P2ROM_OFFSET   = 27'h0300000; // P2+:        $0300000~...

	wire [26:0] ioctl_addr_offset =
		(ioctl_index == INDEX_SPROM)   ?	{SPROM_OFFSET[26:19]  , ioctl_addr[18:0]} : // System ROM: $0000000~$007FFFF
		(ioctl_index == INDEX_SFIXROM) ? {SFIXROM_OFFSET[26:17], ioctl_addr[16:0]} : // SFIX:       $0020000~$003FFFF (in sys ROM)
		(ioctl_index == INDEX_S1ROM)   ?	{S1ROM_OFFSET[26:19]  , ioctl_addr[18:0]} : // S1:         $0080000~$00FFFFF
		(ioctl_index == INDEX_P1ROM_A) ?  P1ROM_A_OFFSET       + ioctl_addr        : // P1+:        $0200000~...
		(ioctl_index == INDEX_P1ROM_B) ? {P1ROM_B_OFFSET[26:19], ioctl_addr[18:0]} : // P1:         $0280000~$02FFFFF (secondary 512KB)
		(ioctl_index == INDEX_P2ROM)   ?  P2ROM_OFFSET         + ioctl_addr        : // P2+:        $0300000~...
		(ioctl_index == INDEX_CROM0)   ? {CROM_START, 20'd0}   + ioctl_addr        : // C:          end of P, consolidated CROM
		(ioctl_index >= INDEX_CROMS)   ? {CROM_START, 20'd0}   + CROM_LOAD_ADDR    : // C*:         end of P
		27'h0100000; // undefined case, use work RAM address to make sure no ROM gets overwritten

	reg  [6:0] CROM_START;
	reg [26:0] P2ROM_MASK, CROM_MASK, V1ROM_MASK, V2ROM_MASK, MROM_MASK;
	always_ff @(posedge clk_sys) begin
		reg old_rst;
		reg old_download;

		old_rst <= status[0];

		if(status[0]) begin
			P2ROM_MASK <= P2ROM_MASK | P2ROM_MASK[26:1];
			CROM_MASK  <= CROM_MASK  | CROM_MASK[26:1];
			V1ROM_MASK <= V1ROM_MASK | V1ROM_MASK[26:1];
			V2ROM_MASK <= V2ROM_MASK | V2ROM_MASK[26:1];
			MROM_MASK  <= MROM_MASK  | MROM_MASK[26:1];
		end

		if(ioctl_wr) begin
			     if(ioctl_index >= INDEX_CROMS)  CROM_MASK  <= CROM_MASK  | CROM_LOAD_ADDR;
			else if(ioctl_index >= INDEX_VROMS) begin
				if(~VROM_LOAD_ADDR[24]) 			 V1ROM_MASK <= V1ROM_MASK | VROM_LOAD_ADDR;
				else  									 V2ROM_MASK <= V2ROM_MASK | VROM_LOAD_ADDR;
			end
			else if(ioctl_index == INDEX_CROM0)  CROM_MASK  <= CROM_MASK  | ioctl_addr;
			else if(ioctl_index == INDEX_M1ROM)  MROM_MASK  <= MROM_MASK  | ioctl_addr;
			else if(ioctl_index == INDEX_P2ROM || ioctl_index == INDEX_P1ROM_A) begin
				if(ioctl_addr_offset >= P2ROM_OFFSET) P2ROM_MASK <= P2ROM_MASK | (ioctl_addr_offset - P2ROM_OFFSET);
			end
			
			if(ioctl_index == INDEX_MEMCP && ioctl_addr == 6 && cp_op) begin
				if(cp_idx >= INDEX_VROMS) begin
					if(cp_idx < (INDEX_VROMS+32)) V1ROM_MASK <= V1ROM_MASK | (cp_end[23:0]-1'd1);
					else  								V2ROM_MASK <= V2ROM_MASK | (cp_end[23:0]-1'd1);
				end
				else if(cp_idx == INDEX_CROM0)  CROM_MASK  <= CROM_MASK  | (cp_size-1'd1);
				else if(cp_idx == INDEX_M1ROM)  MROM_MASK  <= MROM_MASK  | (cp_size-1'd1);
				else if(cp_idx == INDEX_P2ROM || cp_idx == INDEX_P1ROM_A) begin
					if((cp_end-1'd1)>=P2ROM_OFFSET) P2ROM_MASK <= P2ROM_MASK | (cp_end - P2ROM_OFFSET - 1'd1);
				end

				if(cp_idx == INDEX_P2ROM || cp_idx == INDEX_P1ROM_A) begin
					if(CROM_START < cp_end[26:20]) CROM_START <= cp_end[26:20];
				end
			end

			if(old_download && ~ioctl_download && (ioctl_index == INDEX_P2ROM || ioctl_index == INDEX_P1ROM_A)) begin
				if(CROM_START < ioctl_addr_offset[26:20]) CROM_START <= ioctl_addr_offset[26:20];
			end
		end

		if(~old_rst & status[0]) begin
			CROM_MASK  <= 0;
			V1ROM_MASK <= 0;
			V2ROM_MASK <= 0;
			MROM_MASK  <= 0;
			P2ROM_MASK <= 0;
			CROM_START <= 3;
		end
		
		old_download <= ioctl_download;
		if(old_download && ~ioctl_download && (ioctl_index == INDEX_P2ROM || ioctl_index == INDEX_P1ROM_A)) begin
			if(CROM_START < ioctl_addr_offset[26:20]) CROM_START <= ioctl_addr_offset[26:20];
		end
	end

	wire SDRAM_WR;
	wire SDRAM_RD;
	wire SDRAM_BURST;
	wire [1:0] SDRAM_BS;
	wire sdr2_en;

	sdram_mux SDRAM_MUX(
		.CLK(clk_sys),
		.nRESET(nRESET),
		.nSYSTEM_G(nSYSTEM_G),
		.SYSTEM_CDx(SYSTEM_CDx),
		
		.M68K_ADDR(M68K_ADDR),
		.M68K_DATA(M68K_DATA),
		.nAS(nAS | (FC1 == FC0)),
		.nLDS(nLDS),
		.nUDS(nUDS),
		.nROMOE(nROMOE),
		.nPORTOE(nPORTOE),
		.nSROMOE(nSROMOE),
		.DATA_TYPE(~FC1 & FC0), // 0 - program, 1 - data, 
		.P2ROM_ADDR(P2ROM_ADDR & P2ROM_MASK),
		.PROM_DATA(PROM_DATA),
		.PROM_DATA_READY(PROM_DATA_READY),

		.CD_TR_AREA(CD_TR_AREA),
		.CD_EXT_RD(CD_EXT_RD),
		.CD_EXT_WR(CD_EXT_WR),
		.CD_WR_SDRAM_SIG(CD_WR_SDRAM_SIG),
		.CD_BANK_SPR(CD_BANK_SPR),

		.DMA_ADDR_OUT(DMA_ADDR_OUT), .DMA_ADDR_IN(DMA_ADDR_IN),
		.DMA_DATA_OUT(DMA_DATA_OUT),
		.DMA_WR_OUT(DMA_WR_OUT),
		.DMA_RUNNING(DMA_RUNNING),
		.DMA_SDRAM_BUSY(DMA_SDRAM_BUSY),

		.PCK1(PCK1),
		.SPR_EN(SPR_EN),
		.CROM_ADDR({CROM_ADDR[26:20] + (SYSTEM_CDx ? 7'd8 : CROM_START), CROM_ADDR[19:0]}),
		.CR_DOUBLE(CR_DOUBLE),

		.PCK2(PCK2),
		.S_LATCH(S_LATCH),
		.FIX_BANK(FIX_BANK),
		.FIX_EN(FIX_EN),
		.SROM_DATA(SROM_DATA),

		.DL_EN(ioctl_download & ioctl_en),
		.DL_ADDR(ioctl_addr_offset),
		.DL_DATA(ioctl_dout),
		.DL_WR(ioctl_wr),

		.SDRAM_ADDR(sdram_addr),
		.SDRAM_DOUT(sdram_dout),
		.SDRAM_DIN(sdram_din),
		.SDRAM_WR(SDRAM_WR),
		.SDRAM_RD(SDRAM_RD),
		.SDRAM_BURST(SDRAM_BURST),
		.SDRAM_BS(SDRAM_BS),
		.SDRAM_READY(sdram_ready)
	);
	
	reg  [1:0] sdr_pri_128_64;
	wire sdr_pri_cpsel = (~sdr_cpaddr[26] | sdr_pri_128_64[1]) & (~sdr_cpaddr[25] | sdr_pri_128_64[0]);
	always @(posedge clk_sys) if (~nRESET) sdr_pri_128_64 <= {~sdram_sz[14] & &sdram_sz[1:0], ~sdram_sz[14] & sdram_sz[1]};

	wire sdram1_ready, sdram2_ready;
	wire [63:0] sdram1_dout, sdram2_dout;

	sdram ram1(
		.SDRAM_CKE(SDRAM_CKE),
		.SDRAM_A(SDRAM_A),
		.SDRAM_BA(SDRAM_BA),
		.SDRAM_DQ(SDRAM_DQ),
		.SDRAM_DQML(SDRAM_DQML),
		.SDRAM_DQMH(SDRAM_DQMH),
		.SDRAM_nCS(SDRAM_nCS),
		.SDRAM_nCAS(SDRAM_nCAS),
		.SDRAM_nRAS(SDRAM_nRAS),
		.SDRAM_nWE(SDRAM_nWE),
		.SDRAM_EN(1),

		.init(~locked),	// Init SDRAM as soon as the PLL is locked
		.clk(clk_sys),
		.addr(sdram_addr[26:1]),
		.sel(sdr_pri_sel),
		.dout(sdram1_dout),
		.din(sdram_din),
		.bs(SDRAM_BS),
		.wr(SDRAM_WR),
		.rd(SDRAM_RD),
		.burst(SDRAM_BURST),
		.ready(sdram1_ready),

		.cpsel(sdr_pri_cpsel),
		.cpaddr(sdr_cpaddr[26:1]),
		.cpdin(sdr_cpdin),
		.cprd(sdr1_cprd),
		.cpreq(sdr_cpreq),
		.cpbusy(sdr1_cpbusy)
	);

`ifdef DUAL_SDRAM
	sdram ram2(
		.SDRAM_A(SDRAM2_A),
		.SDRAM_BA(SDRAM2_BA),
		.SDRAM_DQ(SDRAM2_DQ),
		.SDRAM_nCS(SDRAM2_nCS),
		.SDRAM_nCAS(SDRAM2_nCAS),
		.SDRAM_nRAS(SDRAM2_nRAS),
		.SDRAM_nWE(SDRAM2_nWE),
		.SDRAM_EN(SDRAM2_EN),

		.init(~locked),	// Init SDRAM as soon as the PLL is locked
		.clk(clk_sys),
		.addr(sdram_addr[25:1]),
		.sel(~sdr_pri_sel),
		.dout(sdram2_dout),
		.din(sdram_din),
		.bs(SDRAM_BS),
		.wr(SDRAM_WR),
		.rd(SDRAM_RD),
		.burst(SDRAM_BURST),
		.ready(sdram2_ready),

		.cpsel(~sdr_pri_cpsel),
		.cpaddr(sdr_cpaddr[25:1]),
		.cpdin(sdr_cpdin),
		.cprd(sdr2_cprd),
		.cpreq(sdr_cpreq),
		.cpbusy(sdr2_cpbusy)
	);

	wire sdr_pri_sel = (~sdram_addr[26] | sdr_pri_128_64[1]) & (~sdram_addr[25] | sdr_pri_128_64[0]);
	assign sdr2_en   = SDRAM2_EN;
`else
	wire   sdr_pri_sel = 1;
	assign sdram2_dout = '0;
	assign sdram2_ready = 1;
	assign sdr2_cprd = 0;
	assign sdr2_cpbusy = 0;
	assign sdr2_en = 0;
`endif

	assign sdram_dout  = sdr_pri_sel ? sdram1_dout : sdram2_dout;
	assign sdram_ready = sdram2_ready & sdram1_ready;

	neo_d0 D0(
		.CLK_24M(CLK_24M),
		.nRESET(nRESET), .nRESETP(nRESETP),
		.CLK_12M(CLK_12M), .CLK_68KCLK(CLK_68KCLK), .CLK_68KCLKB(CLK_68KCLKB), .CLK_6MB(CLK_6MB), .CLK_1HB(CLK_1HB),
		.M68K_ADDR_A4(M68K_ADDR[4]),
		.M68K_DATA(M68K_DATA[5:0]),
		.nBITWD0(nBITWD0),
		.SDA_H(SDA[15:11]), .SDA_L(SDA[4:2]),
		.nSDRD(nSDRD),	.nSDWR(nSDWR), .nMREQ(nMREQ),	.nIORQ(nIORQ),
		.nZ80NMI(nZ80NMI),
		.nSDW(nSDW), .nSDZ80R(nSDZ80R), .nSDZ80W(nSDZ80W),	.nSDZ80CLR(nSDZ80CLR),
		.nSDROM(nSDROM), .nSDMRD(nSDMRD), .nSDMWR(nSDMWR), .nZRAMCS(nZRAMCS),
		.SDRD0(SDRD0),	.SDRD1(SDRD1),
		.n2610CS(n2610CS), .n2610RD(n2610RD), .n2610WR(n2610WR),
		.BNK(BNK)
	);
	
	// Re-priority-encode the interrupt lines with the CD_IRQ one (IPL* are active-low)
	// Also swap IPL0 and IPL1 for CD systems
	//                      Cartridge     		CD
	// CD_IRQ IPL1 IPL0		IPL2 IPL1 IPL0		IPL2 IPL1 IPL0
	//    0     1    1		  1    1    1  	  1    1    1	No IRQ
	//    0     1    0        1    1    0		  1    0    1	Vblank
	//    0     0    1        1    0    1		  1    1    0  Timer
	//    0     0    0        1    0    0		  1    0    0	Cold boot
	//    1     x    x        1    1    1  	  0    1    1	CD vectored IRQ
	wire IPL0_OUT = SYSTEM_CDx ? CD_IRQ | IPL1 : IPL0;
	wire IPL1_OUT = SYSTEM_CDx ? CD_IRQ | IPL0 : IPL1;
	wire IPL2_OUT = ~(SYSTEM_CDx & CD_IRQ);
	
	// Because of the SDRAM latency, nDTACK is handled differently for ROM zones
	// If the address is in a ROM zone, PROM_DATA_READY is used to extend the normal nDTACK output by NEO-C1
	wire nDTACK_ADJ = ~&{nSROMOE, nROMOE, nPORTOE, ~CD_EXT_RD} ? ~PROM_DATA_READY | nDTACK : nDTACK;
	
	cpu_68k M68KCPU(
		.CLK_24M(CLK_24M),
		.nRESET(nRESET_WD),
		.M68K_ADDR(M68K_ADDR),
		.FX68K_DATAIN(FX68K_DATAIN), .FX68K_DATAOUT(FX68K_DATAOUT),
		.nLDS(nLDS), .nUDS(nUDS), .nAS(nAS), .M68K_RW(M68K_RW),
		.nDTACK(nDTACK_ADJ),	// nDTACK
		.IPL2(IPL2_OUT), .IPL1(IPL1_OUT), .IPL0(IPL0_OUT),
		.FC2(FC2), .FC1(FC1), .FC0(FC0),
		.nBG(nBG), .nBR(nBR), .nBGACK(nBGACK)
	);
	
	wire IACK = &{FC2, FC1, FC0};
	
	// FX68K doesn't like byte masking with Z's, replace with 0's:
	assign M68K_DATA_BYTE_MASK = (~|{nLDS, nUDS}) ? M68K_DATA :
											(~nLDS) ? {8'h00, M68K_DATA[7:0]} :
											(~nUDS) ? {M68K_DATA[15:8], 8'h00} :
											16'h0000;

	assign M68K_DATA = M68K_RW ? 16'bzzzzzzzz_zzzzzzzz : FX68K_DATAOUT;
	assign FX68K_DATAIN = M68K_RW ? M68K_DATA_BYTE_MASK : 16'h0000;
	
	assign FIXD = S2H1 ? SROM_DATA[15:8] : SROM_DATA[7:0];
	
	// Disable ROM read in PORT zone if the game uses a special chip
	assign M68K_DATA = (nROMOE & nSROMOE & |{nPORTOE, cart_chip, cart_pchip}) ? 16'bzzzzzzzzzzzzzzzz : PROM_DATA;

	// 68k work RAM
	dpram #(15) WRAML(
		.clock_a(CLK_24M),
		.address_a(M68K_ADDR[15:1]),
		.data_a(M68K_DATA[7:0]),
		.wren_a(~nWWL),
		.q_a(WRAML_OUT),

		.clock_b(CLK_24M),
		.address_b(TRASH_ADDR),
		.data_b(TRASH_ADDR[7:0]),
		.wren_b(~nRESET)
	);

	dpram #(15) WRAMU(
		.clock_a(CLK_24M),
		.address_a(M68K_ADDR[15:1]),
		.data_a(M68K_DATA[15:8]),
		.wren_a(~nWWU),
		.q_a(WRAMU_OUT),

		.clock_b(CLK_24M),
		.address_b(TRASH_ADDR),
		.data_b(TRASH_ADDR[7:0]),
		.wren_b(~nRESET)
	);
	
	wire [23:0] P2ROM_ADDR = (!cart_pchip) ? {P_BANK, M68K_ADDR[19:1], 1'b0} : 24'bZ;
	
	neo_pvc neo_pvc
	(
		.nRESET(nRESET),
		.CLK_24M(CLK_24M),

		.ENABLE(cart_pchip == 2),

		.M68K_ADDR(M68K_ADDR),
		.M68K_DATA(M68K_DATA),
		.PROM_DATA(PROM_DATA),
		.nPORTOEL(nPORTOEL),
		.nPORTOEU(nPORTOEU),
		.nPORTWEL(nPORTWEL),
		.nPORTWEU(nPORTWEU),
		.P2_ADDR(P2ROM_ADDR)
	);
	
	neo_sma neo_sma
	(
		.nRESET(nRESET),
		.CLK_24M(CLK_24M),

		.TYPE(cart_pchip),

		.M68K_ADDR(M68K_ADDR),
		.M68K_DATA(M68K_DATA),
		.PROM_DATA(PROM_DATA),
		.nPORTOEL(nPORTOEL),
		.nPORTOEU(nPORTOEU),
		.nPORTWEL(nPORTWEL),
		.nPORTWEU(nPORTWEU),
		.P2_ADDR(P2ROM_ADDR)
	);
	

	// Work RAM or CD extended RAM read
	assign M68K_DATA[7:0]  = nWRL ? 8'bzzzzzzzz : SYSTEM_CDx ? PROM_DATA[7:0]  : WRAML_OUT;
	assign M68K_DATA[15:8] = nWRU ? 8'bzzzzzzzz : SYSTEM_CDx ? PROM_DATA[15:8] : WRAMU_OUT;
	
	wire save_wr    = (!SYSTEM_CDx || (sd_req_type == 16'h0000)) & sd_buff_wr & sd_ack;
	wire sram_wr    = ~sd_lba[7] & save_wr; // 000000~00FFFF
	wire memcard_wr =  sd_lba[7] & save_wr; // 010000-011FFF
	wire [14:0] sram_addr    = {sd_lba[6:0], sd_buff_addr}; //64KB
	wire [11:0] memcard_addr = {sd_lba[3:0], sd_buff_addr}; //8KB

	// Backup RAM
	wire nBWL = nSRAMWEL | nSRAMWEN_G;
	wire nBWU = nSRAMWEU | nSRAMWEN_G;

	wire [15:0] sd_buff_din_sram;
	backup BACKUP(
		.CLK_24M(CLK_24M),
		.M68K_ADDR(M68K_ADDR[15:1]),
		.M68K_DATA(M68K_DATA),
		.nBWL(nBWL), .nBWU(nBWU),
		.SRAM_OUT(SRAM_OUT),
		.clk_sys(clk_sys),
		.sram_addr(sram_addr),
		.sram_wr(sram_wr),
		.sd_buff_dout(sd_buff_dout),
		.sd_buff_din_sram(sd_buff_din_sram)
	);
	
	// Backup RAM is only for MVS
	assign M68K_DATA[7:0] = (nSRAMOEL | ~SYSTEM_MVS) ? 8'bzzzzzzzz : SRAM_OUT[7:0];
	assign M68K_DATA[15:8] = (nSRAMOEU | ~SYSTEM_MVS) ? 8'bzzzzzzzz : SRAM_OUT[15:8];
	
	// Memory card
	assign {nCD1, nCD2} = {2{status[4] & ~SYSTEM_CDx}};	// Always plugged in CD systems
	assign CARD_WE = (SYSTEM_CDx | (~nCARDWEN & CARDWENB)) & ~nCRDW;
	
	wire [15:0] sd_buff_din_memcard;
	memcard MEMCARD(
		.CLK_24M(CLK_24M),
		.SYSTEM_CDx(SYSTEM_CDx),
		.CDA(CDA), .CDD(CDD),
		.CARD_WE(CARD_WE),
		.M68K_DATA(M68K_DATA[7:0]),
		.clk_sys(clk_sys),
		.memcard_addr(memcard_addr),
		.memcard_wr(memcard_wr),
		.sd_buff_dout(sd_buff_dout),
		.sd_buff_din_memcard(sd_buff_din_memcard)
	);
	
	// Feed save file writer with backup RAM data or memory card data
	assign sd_buff_din = SYSTEM_CDx ? sd_buff_din_memcard :
								sd_lba[7] ? sd_buff_din_memcard : sd_buff_din_sram;
	
	assign CROM_ADDR = {C_LATCH_EXT, C_LATCH, 3'b000} & CROM_MASK;

	zmc ZMC(
		.nRESET(nRESET),
		.nSDRD0(SDRD0),
		.SDA_L(SDA[1:0]), .SDA_U(SDA[15:8]),
		.MA(MA)
	);

	// Bankswitching for the PORT zone, do all games use a 1MB window ?
	// P_BANK stays at 0 for CD systems
	always @(posedge nPORTWEL or negedge nRESET)
	begin
		if (!nRESET)
			P_BANK <= 0;
		else
			if (!SYSTEM_CDx) P_BANK <= M68K_DATA[3:0];
	end
	
	// PRO-CT0 used as security chip
	wire [3:0] GAD_SEC;
	wire [3:0] GBD_SEC;
	
	zmc2_dot ZMC2DOT(
		.CLK_12M(nPORTWEL),
		.EVEN(M68K_ADDR[2]), .LOAD(M68K_ADDR[1]), .H(M68K_ADDR[3]),
		.CR({
			M68K_ADDR[19], M68K_ADDR[15], M68K_ADDR[18], M68K_ADDR[14],
			M68K_ADDR[17], M68K_ADDR[13], M68K_ADDR[16], M68K_ADDR[12],
			M68K_ADDR[11], M68K_ADDR[7], M68K_ADDR[10], M68K_ADDR[6],
			M68K_ADDR[9], M68K_ADDR[5], M68K_ADDR[8], M68K_ADDR[4],
			M68K_DATA[15], M68K_DATA[11], M68K_DATA[14], M68K_DATA[10],
			M68K_DATA[13], M68K_DATA[9], M68K_DATA[12], M68K_DATA[8],
			M68K_DATA[7], M68K_DATA[3], M68K_DATA[6], M68K_DATA[2],
			M68K_DATA[5], M68K_DATA[1], M68K_DATA[4], M68K_DATA[0]
			}),
		.GAD(GAD_SEC), .GBD(GBD_SEC)
	);	
	
	assign M68K_DATA[7:0] = ((cart_chip == 1) & ~nPORTOEL) ?
									{GBD_SEC[1], GBD_SEC[0], GBD_SEC[3], GBD_SEC[2],
									GAD_SEC[1], GAD_SEC[0], GAD_SEC[3], GAD_SEC[2]} : 8'bzzzzzzzz;

	neo_273 NEO273(
		.PBUS(PBUS[19:0]),
		.PCK1B(~PCK1), .PCK2B(~PCK2),
		.C_LATCH(C_LATCH), .S_LATCH(S_LATCH)
	);
	
	// 4 MSBs not handled by NEO-273
	always @(negedge PCK1)
		C_LATCH_EXT <= PBUS[23:20];
	
	neo_cmc neo_cmc
	(
		.PCK2B(~PCK2),
		.PBUS(PBUS[14:0]),
		.TYPE(cmc_chip),
		.ADDR(FIXMAP_ADDR),
		.BANK(FIX_BANK)
	);
	

	// Fake COM MCU
	wire [15:0] COM_DOUT;
	
	com COM(
		.nRESET(nRESET),
		.CLK_24M(CLK_24M),
		.nPORTOEL(nPORTOEL), .nPORTOEU(nPORTOEU), .nPORTWEL(nPORTWEL),
		.M68K_DIN(COM_DOUT)
	);
	
	assign M68K_DATA = (cart_chip == 2) ? COM_DOUT : 16'bzzzzzzzz_zzzzzzzz;
	
	syslatch SL(
		.nRESET(nRESET),
		.CLK_68KCLK(CLK_68KCLK),
		.M68K_ADDR(M68K_ADDR[4:1]),
		.nBITW1(nBITW1),
		.SHADOW(SHADOW), .nVEC(nVEC), .nCARDWEN(nCARDWEN),	.CARDWENB(CARDWENB), .nREGEN(nREGEN), .nSYSTEM(nSYSTEM), .nSRAMWEN(nSRAMWEN), .PALBNK(PALBNK)
	);
	
	wire nSRAMWEN_G = SYSTEM_MVS ? nSRAMWEN : 1'b1;	// nSRAMWEN is only for MVS
	wire nSYSTEM_G = SYSTEM_MVS ? nSYSTEM : 1'b1;	// nSYSTEM is only for MVS
	
	neo_e0 E0(
		.M68K_ADDR(M68K_ADDR[23:1]),
		.BNK(BNK),
		.nSROMOEU(nSROMOEU),	.nSROMOEL(nSROMOEL), .nSROMOE(nSROMOE),
		.nVEC(nVEC),
		.A23Z(A23Z), .A22Z(A22Z),
		.CDA(CDA)
	);
	
	neo_f0 F0(
		.nRESET(nRESET),
		.nDIPRD0(nDIPRD0), .nDIPRD1(nDIPRD1),
		.nBITW0(nBITW0), .nBITWD0(nBITWD0),
		.DIPSW({~status[9:8], 5'b11111, ~status[7]}),
		.COIN1(~joystick_0[10]), .COIN2(~joystick_1[10]),
		.M68K_ADDR(M68K_ADDR[7:4]),
		.M68K_DATA(M68K_DATA[7:0]),
		.SYSTEMB(~nSYSTEM_G),
		.RTC_DOUT(RTC_DOUT), .RTC_TP(RTC_TP), .RTC_DIN(RTC_DIN), .RTC_CLK(RTC_CLK), .RTC_STROBE(RTC_STROBE),
		.SYSTEM_TYPE(SYSTEM_MVS)
	);
	
	uPD4990 RTC(
		.rtc(rtc),
		.nRESET(nRESET),
		.CLK(CLK_12M),
		.DATA_CLK(RTC_CLK), .STROBE(RTC_STROBE),
		.DATA_IN(RTC_DIN), .DATA_OUT(RTC_DOUT),
		.CS(1'b1), .OE(1'b1),
		.TP(RTC_TP)
	);
	
	neo_g0 G0(
		.M68K_DATA(M68K_DATA),
		.G0(nCRDC), .G1(nPAL), .DIR(M68K_RW), .WE(nPAL_WE),
		.CDD({8'hFF, CDD}), .PC(PAL_RAM_DATA)
	);

	neo_c1 C1(
		.M68K_ADDR(M68K_ADDR[21:17]),
		.M68K_DATA(M68K_DATA[15:8]), .A22Z(A22Z), .A23Z(A23Z),
		.nLDS(nLDS), .nUDS(nUDS), .RW(M68K_RW), .nAS(nAS),
		.nROMOEL(nROMOEL), .nROMOEU(nROMOEU),
		.nPORTOEL(nPORTOEL), .nPORTOEU(nPORTOEU), .nPORTWEL(nPORTWEL), .nPORTWEU(nPORTWEU),
		.nPORT_ZONE(nPORTADRS),
		.nWRL(nWRL), .nWRU(nWRU), .nWWL(nWWL), .nWWU(nWWU),
		.nSROMOEL(nSROMOEL), .nSROMOEU(nSROMOEU),
		.nSRAMOEL(nSRAMOEL), .nSRAMOEU(nSRAMOEU), .nSRAMWEL(nSRAMWEL), .nSRAMWEU(nSRAMWEU),
		.nLSPOE(nLSPOE), .nLSPWE(nLSPWE),
		.nCRDO(nCRDO), .nCRDW(nCRDW), .nCRDC(nCRDC),
		.nSDW(nSDW),
		.P1_IN(~{joystick_0[9:4] | {3{joystick_0[11]}}, joystick_0[0], joystick_0[1], joystick_0[2], joystick_0[3]}),
		.P2_IN(~{joystick_1[9:4] | {3{joystick_1[11]}}, joystick_1[0], joystick_1[1], joystick_1[2], joystick_1[3]}),
		.nCD1(nCD1), .nCD2(nCD2),
		.nWP(0),			// Memory card is never write-protected
		.nROMWAIT(1), .nPWAIT0(1), .nPWAIT1(1), .PDTACK(1),
		.SDD_WR(SDD_OUT),
		.SDD_RD(SDD_RD_C1),
		.nSDZ80R(nSDZ80R), .nSDZ80W(nSDZ80W), .nSDZ80CLR(nSDZ80CLR),
		.CLK_68KCLK(CLK_68KCLK),
		.nDTACK(nDTACK),
		.nBITW0(nBITW0), .nBITW1(nBITW1),
		.nDIPRD0(nDIPRD0), .nDIPRD1(nDIPRD1),
		.nPAL_ZONE(nPAL),
		.SYSTEM_TYPE(SYSTEM_TYPE)
	);

	// This is used to split burst-read sprite gfx data in half at the right time
	reg LOAD_SR;
	reg CA4_REG;
	
	// CA4's polarity depends on the tile's h-flip attribute
	// Normal: CA4 high, then low
	// Flipped: CA4 low, then high
	always @(posedge CLK_24M) begin
		LOAD_SR <= LOAD;
		if (~LOAD_SR & LOAD) CA4_REG <= CA4;
	end
	
	// CR_DOUBLE: [8px left] [8px right]
	//         BP  A B C D    A B C D
	wire [31:0] CR = CA4_REG ? CR_DOUBLE[63:32] : CR_DOUBLE[31:0];
	
	neo_zmc2 ZMC2(
		.CLK_12M(CLK_12M),
		.EVEN(EVEN1), .LOAD(LOAD), .H(H),
		.CR(CR),
		.GAD(GAD), .GBD(GBD),
		.DOTA(DOTA), .DOTB(DOTB)
	);
	
	dpram #(16) LO(
		.clock_a(clk_sys),
		.address_a(ioctl_addr[16:1]),
		.data_a(ioctl_dout[7:0]),
		.wren_a(ioctl_download & (ioctl_index == INDEX_LOROM) & ioctl_wr),
		.clock_b(CLK_24M),
		.address_b(PBUS[15:0]),
		.q_b(LO_ROM_DATA)
	);

	// VCS is normally used as the LO ROM's nOE but the NeoGeo relies on the fact that the LO ROM
	// will still have its output active for a short moment (~50ns) after nOE goes high
	// nPBUS_OUT_EN is used internally by LSPC2 but it's broken out here to use the additional
	// half mclk cycle it provides compared to VCS. This makes sure LO_ROM_DATA is valid when latched.
	assign PBUS[23:16] = nPBUS_OUT_EN ? LO_ROM_DATA : 8'bzzzzzzzz;
	
	spram #(11,16) UFV(
		.clock(CLK_24M),	//~CLK_24M,		// Is just CLK ok ?
		.address(FAST_VRAM_ADDR),
		.data(FAST_VRAM_DATA_OUT),
		.wren(~CWE),
		.q(FAST_VRAM_DATA_IN)
	);
	
	spram #(15,16) USV(
		.clock(CLK_24M),	//~CLK_24M,		// Is just CLK ok ?
		.address(SLOW_VRAM_ADDR),
		.data(SLOW_VRAM_DATA_OUT),
		.wren(~BWE),
		.q(SLOW_VRAM_DATA_IN)
	);

	wire [18:11] MA;
	wire [7:0] Z80_RAM_DATA;

	spram #(11) Z80RAM(.clock(CLK_4M), .address(SDA[10:0]), .data(SDD_OUT), .wren(~(nZRAMCS | nSDMWR)), .q(Z80_RAM_DATA));	// Fast enough ?

	assign SDD_IN = (~nSDZ80R) ? SDD_RD_C1 :
						(~nSDMRD & ~nSDROM) ? M1_ROM_DATA :
						(~nSDMRD & ~nZRAMCS) ? Z80_RAM_DATA :
						(~n2610CS & ~n2610RD) ? YM2610_DOUT :
						8'b00000000;
	
	wire Z80_nRESET = SYSTEM_CDx ? nRESET & CD_nRESET_Z80 : nRESET;

	wire [7:0] M1_ROM_DATA;
	reg nZ80WAIT;
	reg z80rd_req;
	wire z80rd_ack;
	wire z80_rom_rd = ~(nSDMRD | nSDROM);
	always @(posedge clk_sys) begin
		reg old_rd, old_rd1;
		reg old_clk;
		
		old_rd <= z80_rom_rd;
		if(old_rd == z80_rom_rd) old_rd1 <= old_rd;
		
		if(~old_rd1 & old_rd) z80rd_req <= ~z80rd_req;
		
		old_clk <= CLK_4M;
		if(old_clk & ~CLK_4M) nZ80WAIT <= ~(z80rd_req ^ z80rd_ack);
	end
	
	cpu_z80 Z80CPU(
		.CLK_4M(CLK_4M),
		.nRESET(Z80_nRESET),
		.SDA(SDA), .SDD_IN(SDD_IN), .SDD_OUT(SDD_OUT),
		.nIORQ(nIORQ),	.nMREQ(nMREQ),	.nRD(nSDRD), .nWR(nSDWR),
		.nINT(nZ80INT), .nNMI(nZ80NMI), .nWAIT(nZ80WAIT)
	);
	
	wire [19:0] ADPCMA_ADDR;
	wire [3:0] ADPCMA_BANK;
	wire [23:0] ADPCMB_ADDR;
	
	reg adpcm_wr, adpcm_rd;
	reg old_download, old_reset;
	wire adpcm_wrack, adpcm_rdack;
	
	wire ddr_loading = ioctl_download & (((ioctl_index >= INDEX_VROMS) & (ioctl_index < INDEX_CROMS)) | (ioctl_index == INDEX_M1ROM));
	reg ddram_wait = 0;
	
	// Copied from Genesis_MiSTer/Genesis.sv
	always @(posedge clk_sys)
	begin
		
		old_download <= ddr_loading;
		old_reset <= nRESET;

		if (old_reset & ~nRESET) ddram_wait <= 0;
		
		if (old_download & ~ddr_loading)
			ddram_wait <= 0;	// Needed ?

		if (~old_download & ddr_loading) begin
			adpcm_wr <= 0;
		end else if (ddr_loading)
		begin
			if (ioctl_wr) begin
				ddram_wait <= 1;
				adpcm_wr <= ~adpcm_wr;
				ddr_waddr <= (ioctl_index == INDEX_M1ROM) ? {1'b1,ioctl_addr[24:0]} : VROM_LOAD_ADDR;
			end else if (ddram_wait & (adpcm_wr == adpcm_wrack)) begin
				ddram_wait <= 0;
			end
		end
	end
	
	assign DDRAM_CLK = clk_sys;
	
	// The ddram request and ack signals work on either edge
	// To trigger a read request, just set adpcm_rd to ~adpcm_rdack
	
	reg ADPCMA_READ_REQ, ADPCMB_READ_REQ;
	reg ADPCMA_READ_ACK, ADPCMB_READ_ACK;
	reg [24:0] ADPCMA_ADDR_LATCH;	// 32MB
	reg [24:0] ADPCMB_ADDR_LATCH;	// 32MB
	
	always @(posedge clk_sys) begin
		reg [1:0] ADPCMA_OE_SR;
		reg [1:0] ADPCMB_OE_SR;
		ADPCMA_OE_SR <= {ADPCMA_OE_SR[0], nSDROE};
		// Trigger ADPCM A data read on nSDROE falling edge
		if (ADPCMA_OE_SR == 2'b10) begin
			ADPCMA_READ_REQ <= ~ADPCMA_READ_REQ;
			ADPCMA_ADDR_LATCH <= {ADPCMA_BANK, ADPCMA_ADDR} & V1ROM_MASK[23:0];
		end
		
		// Trigger ADPCM A data read on nSDPOE falling edge
		ADPCMB_OE_SR <= {ADPCMB_OE_SR[0], nSDPOE};
		if (ADPCMB_OE_SR == 2'b10) begin
			ADPCMB_READ_REQ <= ~ADPCMB_READ_REQ;
			ADPCMB_ADDR_LATCH <= {~use_pcm, ADPCMB_ADDR & (use_pcm ? V1ROM_MASK[23:0] : V2ROM_MASK[23:0])};
		end
	end

	wire [7:0] ADPCMA_DATA;
	wire [7:0] ADPCMB_DATA;
	reg [27:0] ddr_waddr;
	ddram DDRAM(
		.*,
		
		.wraddr(ddr_waddr),
		.din(ioctl_dout),
		.we_req(adpcm_wr),
		.we_ack(adpcm_wrack),
		
		.rdaddr(ADPCMA_ADDR_LATCH),
		.dout(ADPCMA_DATA),
		.rd_req(ADPCMA_READ_REQ),
		.rd_ack(ADPCMA_READ_ACK),

		.rdaddr2(ADPCMB_ADDR_LATCH),
		.dout2(ADPCMB_DATA),
		.rd_req2(ADPCMB_READ_REQ),
		.rd_ack2(ADPCMB_READ_ACK),

		.rdaddr3({7'b10_0000_0,MA & MROM_MASK[18:11],SDA[10:0]}),
		.dout3(M1_ROM_DATA),
		.rd_req3(z80rd_req),
		.rd_ack3(z80rd_ack),

		.cpaddr({1'b1, ddr_cpaddr}),
		.cpdout(ddr_cpdout),
		.cpwr(ddr_cpwr),
		.cpreq(ddr_cpreq),
		.cpbusy(ddr_cpbusy)
	);
	
	wire [26:0] ddr_cpaddr = cur_off;
	wire [63:0] ddr_cpdout;
	wire        ddr_cpwr;
	wire        ddr_cpbusy;
	reg         ddr_cpreq;
	wire [26:0] sdr_cpaddr = cp_addr + cur_off;
	wire [15:0] sdr_cpdin;
	wire        sdr1_cprd, sdr2_cprd;
	wire        sdr_cprd = sdr1_cprd | sdr2_cprd;
	wire        sdr1_cpbusy, sdr2_cpbusy;
	wire        sdr_cpbusy = sdr1_cpbusy | sdr2_cpbusy;
	reg         sdr_cpreq;

	cpram cpram
	(
		.clock(clk_sys),
		.reset(~memcp_wait),

		.wr(ddr_cpwr),
		.data(ddr_cpdout),

		.rd(sdr_cprd),
		.q(sdr_cpdin)
	);

	reg         cp_op;
	reg   [7:0] cp_idx;
	reg  [26:0] cp_size;
	reg  [26:0] cp_addr;
	reg  [26:0] cp_last;
	reg  [26:0] cur_off;

	reg  [26:0] cp_end;

	wire [26:0] cp_offset =
		(cp_idx == INDEX_SPROM)   ? SPROM_OFFSET       :
		(cp_idx == INDEX_SFIXROM) ? SFIXROM_OFFSET     :
		(cp_idx == INDEX_S1ROM)   ? S1ROM_OFFSET       :
		(cp_idx == INDEX_P1ROM_A) ? P1ROM_A_OFFSET     :
		(cp_idx == INDEX_P1ROM_B) ? P1ROM_B_OFFSET     :
		(cp_idx == INDEX_P2ROM)   ? P2ROM_OFFSET       :
		(cp_idx == INDEX_CROM0)   ? {CROM_START, 20'd0}:
		(cp_idx >= INDEX_VROMS)   ? ({cp_idx[7:0]-INDEX_VROMS[7:0], 19'h00000}) :
		                            27'd0;

	reg memcp_wait = 0;
	always @(posedge clk_sys) begin
		reg [1:0] state = 0;

		if(ioctl_download && ioctl_index == INDEX_MEMCP) begin
			if(ioctl_wr) begin
				case(ioctl_addr[3:0])
					0: {cp_op,cp_idx} <= {~ioctl_dout[15],ioctl_dout[7:0]};
					2: cp_size[15:0]  <= ioctl_dout;
					4: begin
							cp_size[26:16] <= ioctl_dout[10:0];
							cp_addr     <= cp_offset;
							cp_end      <= cp_offset + {ioctl_dout[10:0], cp_size[15:0]};
						end
					6: if(ioctl_dout && cp_op) memcp_wait  <= 1;
				endcase

				if(~cp_op) begin
					case(ioctl_addr[3:0])
						2: cfg[15:0]  <= ioctl_dout;
						4: cfg[31:16] <= ioctl_dout;
					endcase
				end
			end
		end

		case(state)
			0: if(~memcp_wait) begin
					ddr_cpreq <= 0;
					sdr_cpreq <= 0;
					cur_off   <= 0;
				end
				else if((~sdr2_en && ~sdr_pri_cpsel) || (cur_off >= cp_size)) memcp_wait <= 0;
				else begin
					ddr_cpreq <= 1;
					state     <= 1;
				end

			1: if(ddr_cpbusy) ddr_cpreq <= 0;
				else if(~ddr_cpreq & ~ddr_cpbusy) begin
					sdr_cpreq <= 1;
					state <= 2;
				end

			2: if(sdr_cpbusy) sdr_cpreq <= 0;
				else if(~sdr_cpreq & ~sdr_cpbusy) begin
					cur_off <= cur_off + 27'd1024;
					state <= 0;
				end
		endcase

		if(~memcp_wait) state <= 0;
	end

	wire [7:0] YM2610_DOUT;

	jt10 YM2610(
		.rst(~nRESET),
		.clk(CLK_8M), .cen(~(ADPCMA_READ_REQ ^ ADPCMA_READ_ACK) & ~(ADPCMB_READ_REQ ^ ADPCMB_READ_ACK)),
		.addr(SDA[1:0]),
		.din(SDD_OUT), .dout(YM2610_DOUT),
		.cs_n(n2610CS), .wr_n(n2610WR),
		.irq_n(nZ80INT),
		.adpcma_addr(ADPCMA_ADDR), .adpcma_bank(ADPCMA_BANK), .adpcma_roe_n(nSDROE), .adpcma_data(ADPCMA_DATA),
		.adpcmb_addr(ADPCMB_ADDR), .adpcmb_roe_n(nSDPOE), .adpcmb_data(SYSTEM_CDx ? 8'h08 : ADPCMB_DATA),	// CD has no ADPCM-B
		.snd_right(snd_right), .snd_left(snd_left), .snd_enable(~{4{dbg_menu}} | ~status[28:25]), .ch_enable(~status[62:57])
	);
	
	 
	// For Neo CD only
	wire VIDEO_EN = SYSTEM_CDx ? CD_VIDEO_EN : 1'b1;
	wire FIX_EN = SYSTEM_CDx ? CD_FIX_EN : 1'b1;
	wire SPR_EN = SYSTEM_CDx ? CD_SPR_EN : 1'b1;
	wire DOTA_GATED = SPR_EN & DOTA;
	wire DOTB_GATED = SPR_EN & DOTB;
	wire HSync; //,VSync;
	
	lspc2_a2	LSPC(
		.CLK_24M(CLK_24M),
		.RESET(nRESET),
		.nRESETP(nRESETP),
		.LSPC_8M(CLK_8M), .LSPC_4M(CLK_4M),
		.M68K_ADDR(M68K_ADDR[3:1]), .M68K_DATA(M68K_DATA),
		.IPL0(IPL0), .IPL1(IPL1),
		.LSPOE(nLSPOE), .LSPWE(nLSPWE),
		.PBUS_OUT(PBUS[15:0]), .PBUS_IO(PBUS[23:16]),
		.nPBUS_OUT_EN(nPBUS_OUT_EN),
		.DOTA(DOTA_GATED), .DOTB(DOTB_GATED),
		.CA4(CA4), .S2H1(S2H1), .S1H1(S1H1),
		.LOAD(LOAD), .H(H), .EVEN1(EVEN1), .EVEN2(EVEN2),
		.PCK1(PCK1), .PCK2(PCK2),
		.CHG(CHG),
		.LD1(LD1), .LD2(LD2),
		.WE(WE), .CK(CK),	.SS1(SS1), .SS2(SS2),
		.HSYNC(HSync), //.VSYNC(VSync),
		.CHBL(CHBL), .BNKB(nBNKB),
		.VCS(VCS),
		.SVRAM_ADDR(SLOW_VRAM_ADDR),
		.SVRAM_DATA_IN(SLOW_VRAM_DATA_IN), .SVRAM_DATA_OUT(SLOW_VRAM_DATA_OUT),
		.BOE(BOE), .BWE(BWE),
		.FVRAM_ADDR(FAST_VRAM_ADDR),
		.FVRAM_DATA_IN(FAST_VRAM_DATA_IN), .FVRAM_DATA_OUT(FAST_VRAM_DATA_OUT),
		.CWE(CWE),
		.VMODE(video_mode),
		.FIXMAP_ADDR(FIXMAP_ADDR)	// Extracted for NEO-CMC
	);
	
	wire nRESET_WD;
	neo_b1 B1(
		.CLK(CLK_24M),	.CLK_6MB(CLK_6MB), .CLK_1HB(CLK_1HB),
		.S1H1(S1H1),
		.A23I(A23Z), .A22I(A22Z),
		.M68K_ADDR_U(M68K_ADDR[21:17]), .M68K_ADDR_L(M68K_ADDR[12:1]),
		.nLDS(nLDS), .RW(M68K_RW), .nAS(nAS),
		.PBUS(PBUS),
		.FIXD(FIXD),
		.PCK1(PCK1), .PCK2(PCK2),
		.CHBL(CHBL), .BNKB(nBNKB),
		.GAD(GAD), .GBD(GBD),
		.WE(WE), .CK(CK),
		.TMS0(CHG), .LD1(LD1), .LD2(LD2), .SS1(SS1), .SS2(SS2),
		.PA(PAL_RAM_ADDR),
		.EN_FIX(FIX_EN),
		.nRST(nRESET),
		.nRESET(nRESET_WD)
	);

	spram #(13,16) PALRAM(
		.clock(CLK_24M), 	// Was CLK_12M
		.address({PALBNK, PAL_RAM_ADDR}),
		.data(M68K_DATA),
		.wren(~nPAL_WE),
		.q(PAL_RAM_DATA)
	);

	// DAC latches
	reg ce_pix;
	reg [2:0] HBlank;
	reg HBlank304;
	always @(posedge CLK_VIDEO) begin
		reg old_clk;
		reg [9:0] pxcnt;

		ce_pix <= 0;
		old_clk <= CLK_6MB;
		if(~old_clk & CLK_6MB) begin
			ce_pix <= 1;
			PAL_RAM_REG <= (nRESET && VIDEO_EN && ((pxcnt >= 7 && pxcnt < 311) || ~status[16])) ? PAL_RAM_DATA : 16'h8000;
		end

		if(ce_pix) begin
			HBlank <= (HBlank<<1) | CHBL;
			
			pxcnt <= pxcnt + 1'b1;
			if(HBlank[1:0] == 2'b10) pxcnt <= 0;
		end
	end
	
	//Re-create VSync as original one is barely equals to VBlank
	reg VSync;
	always @(posedge CLK_VIDEO) begin
		reg       old_hs;
		reg       old_vbl;
		reg [2:0] vbl;
		reg [7:0] vblcnt, vspos;
		
		if(ce_pix) begin
			old_hs <= HSync;
			if(~old_hs & HSync) begin
				old_vbl <= nBNKB;
				
				if(~nBNKB) vblcnt <= vblcnt+1'd1;
				if(old_vbl & ~nBNKB) vblcnt <= 0;
				if(~old_vbl & nBNKB) vspos <= (vblcnt>>1) - 8'd7;

				{VSync,vbl} <= {vbl,1'b0};
				if(vblcnt == vspos) {VSync,vbl} <= '1;
			end
		end
	end
	
	assign VGA_SL = scale ? scale[1:0] - 1'd1 : 2'd0;
	assign VGA_F1 = 0;

	wire [2:0] scale = status[20:18];

	wire [6:0] R6 = {1'b0, PAL_RAM_REG[11:8], PAL_RAM_REG[14], PAL_RAM_REG[11]} - PAL_RAM_REG[15];
	wire [6:0] G6 = {1'b0, PAL_RAM_REG[7:4],  PAL_RAM_REG[13], PAL_RAM_REG[7] } - PAL_RAM_REG[15];
	wire [6:0] B6 = {1'b0, PAL_RAM_REG[3:0],  PAL_RAM_REG[12], PAL_RAM_REG[3] } - PAL_RAM_REG[15];

	wire [7:0] R8 = R6[6] ? 8'd0 : {R6[5:0],  R6[5:4]};
	wire [7:0] G8 = G6[6] ? 8'd0 : {G6[5:0],  G6[5:4]};
	wire [7:0] B8 = B6[6] ? 8'd0 : {B6[5:0],  B6[5:4]};

	wire [7:0] r,g,b;
	wire hs,vs,hblank,vblank;
	video_cleaner video_cleaner
	(
		.clk_vid(CLK_VIDEO),
		.ce_pix(ce_pix),

		.R(~SHADOW ? R8 : {1'b0, R8[7:1]}),
		.G(~SHADOW ? G8 : {1'b0, G8[7:1]}),
		.B(~SHADOW ? B8 : {1'b0, B8[7:1]}),

		.HSync(HSync),
		.VSync(VSync),
		.HBlank(HBlank[2]),
		.VBlank(~nBNKB),

		.VGA_R(r),
		.VGA_G(g),
		.VGA_B(b),
		.VGA_VS(vs),
		.VGA_HS(hs),
		.HBlank_out(hblank),
		.VBlank_out(vblank)
	);
	
	video_mixer #(.LINE_LENGTH(320), .HALF_DEPTH(0), .GAMMA(1)) video_mixer
	(
		.*,

		.clk_vid(CLK_VIDEO),
		.ce_pix(ce_pix),
		.ce_pix_out(CE_PIXEL),

		.scanlines(0),
		.scandoubler(scale || forced_scandoubler),
		.hq2x(scale==1),

		.mono(0),

		.R(r),
		.G(g),
		.B(b),

		// Positive pulses.
		.HSync(hs),
		.VSync(vs),
		.HBlank(hblank),
		.VBlank(vblank)
	);

endmodule
