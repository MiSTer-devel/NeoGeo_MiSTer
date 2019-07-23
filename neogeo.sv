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

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

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
	// 2..5 - USR1..USR4
	// Set USER_OUT to 1 to read from USER_IN.
	input   [5:0] USER_IN,
	output  [5:0] USER_OUT,

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

assign VGA_SL = 0;
assign VGA_F1 = 0;

assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign VIDEO_ARX = 8'd10;	// 320/32
assign VIDEO_ARY = 8'd7;	// 224/32

// status bit definition:
// 31       23       15       7
// --AA-PSS -------- L--CGGDD DEEMVTTR
// R:	status[0]		Reset, used by the HPS, keep it there
// T:	status[2:1]		System type, 0=Console, 1=Arcade, 2=CD, 3=CDZ
// V: status[3]		Video mode
// M: status[4]		Memory card presence
// E:	status[6:5]		Stereo mix
// D:	status[9:7]		DIP switches
// G:	status[11:10]	Neo CD region
// C:	status[12]		Save memory card & backup RAM
// L:	status[12]		CD lid state (DEBUG)
// S:	status[25:24]	Special chip type, 0=None, 1=PRO-CT0, 2=Link MCU, 3=NEO-CMC
// P:	status[26]		Use PCM chip or not
// A: status[29:28]	Sprite tile # remap hack, 0=no remap, 1=kof95, 2=whp, 3=kizuna

`include "build_id.v"

// Conditional modification of the CONF strings chaining according to chosen system type
// Con Arc CD CDz
// 00  01  10 11
// F   F   +  +  ~SYSTEM_CDx;
// +   +   S  S  SYSTEM_CDx; 
// O   O   +  +  ~SYSTEM_CDx;
// +   O   +  +  SYSTEM_MVS; 
// +   +   O  O  SYSTEM_CDx;   

localparam CONF_STR = {
	"NEOGEO;;",
	"-;",
	"H0FS1,EP1P1,Load romset;",
	"H1S0,ISOBIN,Load CD Image;",
	"-;",
	"O12,System type,Console(AES),Arcade(MVS),CD,CDZ;",
	"O3,Video mode,NTSC,PAL;",
	"-;",
	"H0O4,Memory card,Plugged,Unplugged;",
	"RC,Save memory card;",
	"H1-;",
	"H1OAB,Region,US,EU,JP,AS;",
	"H1OF,CD lid,Opened,Closed;",
	"H2-;",
	"H2O7,DIP:Settings,OFF,ON;",
	"H2O8,DIP:Freeplay,OFF,ON;",
	"H2O9,DIP:Freeze,OFF,ON;",
	"-;",
	"O56,Stereo mix,none,25%,50%,100%;",
	"-;",
	"R0,Reset & apply;",
	"J1,A,B,C,D,Start,Select,Coin,ABC;",	// ABC is a special key to press A+B+C at once, useful for
	"V,v",`BUILD_DATE								// keyboards that don't allow more than 2 keypresses at once
};


////////////////////   CLOCKS   ///////////////////

wire locked;
wire clk_sys;

// 50MHz in, 4*24=96MHz out
// CAS latency = 2 (20.8ns)
pll pll(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(SDRAM_CLK),	// Phase shifted
	.outclk_2(SDRAM2_CLK),	// Phase shifted
	.locked(locked)
);

wire nRST = ~(ioctl_download | status[0] | buttons[1]);

// The watchdog should output nRESET but it makes video sync stop for a moment, so the
// MiSTer OSD jumps around. Provide an indication for devs that a watchdog reset happened ?
//wire nRESET = nRST;
reg nRESET;
reg nRST_PREV_24M;
reg [15:0] TRASH_ADDR;
reg TRASHING;

always @(posedge CLK_24M)
begin
	nRST_PREV_24M <= nRST;
	// nRST rising edge: start RAM trashing
	if (~nRST_PREV_24M & nRST)
	begin
		TRASHING <= 1;
		TRASH_ADDR <= 16'h0000;
	end
	// nRST falling edge: put system in reset
	if (nRST_PREV_24M & ~nRST)
		nRESET <= 0;
	
	if (TRASHING)
	begin
		if (TRASH_ADDR == 16'hFFFF)
		begin
			// Trashing done: release system reset
			TRASHING <= 0;
			nRESET <= 1;
		end
		else
			TRASH_ADDR <= TRASH_ADDR + 1'b1;
	end
end

wire CLK_24M;
reg [2:0] counter_p = 0;	// 0~4
reg diva, divb;
reg nRST_PREV;
reg [1:0] SYSTEM_TYPE;

always @(posedge clk_sys)
begin
	nRST_PREV <= nRST;
	
	if ({nRST_PREV, nRST} == 2'b01)
	begin
		// Rising edge of nRST
		counter_p <= 3'd0;
		diva <= 1'd0;
	end
	else
	begin
		if (counter_p == 3'd3)
			counter_p <= 3'd0;
		else
			counter_p <= counter_p + 3'd1;
		
		if (counter_p == 3'd0)
			diva <= ~diva;
	end
end

always @(negedge clk_sys)
begin	
	if ({nRST_PREV, nRST} == 2'b01)
	begin
		// Rising edge of nRST
		SYSTEM_TYPE <= status[2:1];	// Latch the system type on reset
		divb <= 1'd0;
	end
	else
	begin
		if (counter_p == 3'd2)
			divb <= ~divb;
	end
end

assign CLK_24M = diva ^ divb;	// Glitch-less divide-by-5

//////////////////   HPS I/O   ///////////////////

// VD 0: CD bin file
// VD 1: CD cue file, let MiSTer binary take care of it, do not touch !
// VD 2: Save file
wire [2:0] img_mounted;
wire [2:0] sd_rd;
wire [2:0] sd_wr;

wire sd_ack, sd_buff_wr, img_readonly;

wire [7:0] sd_buff_addr;	// Address inside 256-word sector
wire [15:0] sd_buff_dout;
wire [15:0] sd_buff_din;
wire [15:0] sd_req_type;
wire [63:0] img_size;
reg ioctl_download_prev;
reg memcard_load = 0;
reg memcard_ena = 0;
reg memcard_loading = 0;
reg memcard_state = 0;
reg memcard_save_prev = 0, sd_ack_prev;
reg [31:0] sd_lba;
wire [31:0] CD_sd_lba;

wire [15:0] joystick_0;	// ----HNLS DCBAUDLR
wire [15:0] joystick_1;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire [31:0] status;

wire [64:0] rtc;

wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire        ioctl_download;
wire  [7:0] ioctl_index;
reg         ioctl_wait = 0;

wire SYSTEM_MVS = (SYSTEM_TYPE == 2'd1);
wire SYSTEM_CDx = SYSTEM_TYPE[1];

hps_io #(.STRLEN($size(CONF_STR)>>3), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	//.ps2_mouse(ps2_mouse),	// Could be used for The Irritating Maze ?
	
	.joystick_0(joystick_0), .joystick_1(joystick_1),
	.buttons(buttons),			// DE10 buttons ?
	.status(status),				// status read (32 bits)
	.status_menumask({~SYSTEM_MVS,~SYSTEM_CDx,SYSTEM_CDx}),
	.RTC(rtc),
	
	// Loading signals
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wait(ioctl_wait),
	
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
	
//////////////////   Her Majesty   ///////////////////

	wire [15:0] snd_right;
	wire [15:0] snd_left;
	wire        sdram_ready;	//, ready_fourth;
	wire [26:0] sdram_addr;
	
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
	reg [1:0] P_BANK;
	
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
	wire [14:0] FIXMAP_ADDR;
	
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
	parameter INDEX_VROMS = 16;
	parameter INDEX_CROMS = 64;
	
	wire memcard_save = status[12];
	wire [1:0] cart_chip = status[25:24];
	wire video_mode = status[3];
	wire use_pcm = status[26];
	
	// Memory card and backup ram image save/load
	always @(posedge clk_sys)
	begin
		ioctl_download_prev <= ioctl_download;
		
		// Disable memcard operations on download start
		if(~ioctl_download_prev & ioctl_download)
			memcard_ena <= 0;

		// Enable memcard operations while not downloading, 'disk' #2 is mounted, has a != 0 size, and is writable
		if(~ioctl_download && img_mounted[2] && img_size && ~img_readonly)
			memcard_ena <= 1;

		// Start memcard image load on download end
		// TODO: Trigger this on reset release, not download end ! Confuses Neo CD
		if (ioctl_download_prev & ~ioctl_download)
			memcard_load <= 1;
		else if (memcard_state)
			memcard_load <= 0;

		memcard_save_prev <= memcard_save;
		sd_ack_prev <= sd_ack;
		
		if (~sd_ack_prev & sd_ack)
			{sd_rd[2], sd_wr[2]} <= 2'b00;
		else
		begin
			if (!memcard_state)
			begin
				// No current memcard operation
				if (memcard_ena & (memcard_load | (~memcard_save_prev & memcard_save)))
				begin
					// Start operation
					memcard_state <= 1;
					memcard_loading <= memcard_load;
					sd_lba <= 32'd0;
					sd_rd[2] <= memcard_load;
					sd_wr[2] <= ~memcard_load;
				end
			end
			else
			begin
				if (sd_ack_prev & ~sd_ack)
				begin
					// On ack falling edge, either increase lba and continue, or stop operation
					if ((SYSTEM_CDx & (sd_lba[7:0] >= 8'd15)) |	// 8kB / 256 words per sector / 2 bytes per word
						(~SYSTEM_CDx & (sd_lba[7:0] >= 8'd131)))	// (64kB + 2kB) / 256 words per sector / 2 bytes per word
					begin
						memcard_loading <= 0;	// Useless ?
						memcard_state <= 0;
					end
					else
					begin
						sd_lba <= sd_lba + 1'd1;
						sd_rd[2] <= memcard_loading;
						sd_wr[2] <= ~memcard_loading;
					end
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
	wire [1:0] wtbt;
	
	wire DMA_SDRAM_BUSY;
	wire SDRAM_WR_PULSE;
	wire SDRAM_RD_PULSE;
	wire sdram_rd_type;
	wire PROM_DATA_READY;

	cd_sys cdsystem(
		.nRESET(nRESET),
		.clk_sys(clk_sys), .CLK_68KCLK(CLK_68KCLK),
		.M68K_ADDR(M68K_ADDR), .M68K_DATA(M68K_DATA), .A22Z(A22Z), .A23Z(A23Z),
		.nLDS(nLDS), .nUDS(nUDS), .M68K_RW(M68K_RW), .nAS(nAS), .nDTACK(nDTACK),
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
		.sd_rd(sd_rd[0]), .sd_ack(sd_ack), .sd_buff_wr(sd_buff_wr),
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
	
	wire [63:0] sdram_dout;
	wire [15:0] sdram_din;
	wire sdram_rd = ioctl_download ? 1'b0 : SDRAM_RD_PULSE;
	
	// ioctl_download is used to load the system ROM on CD systems, we need it !
	wire sdram_we = SYSTEM_CDx ? (ioctl_download & (ioctl_index == INDEX_SPROM)) ? ioctl_wr : SDRAM_WR_PULSE :
							(ioctl_download & (ioctl_index != INDEX_LOROM) & (ioctl_index != INDEX_M1ROM) & ((ioctl_index < INDEX_VROMS) | (ioctl_index >= INDEX_CROMS))) ? ioctl_wr : 1'b0;
	
	wire [26:0] ioctl_addr_offset =
		(ioctl_index == INDEX_SPROM) ?	{8'b000_0110_0, ioctl_addr[18:0]} :	// System ROM: $0600000~$067FFFF
		(ioctl_index == INDEX_S1ROM) ?	{8'b000_0110_1, ioctl_addr[18:0]} :	// S1: $0680000~$07FFFFF
		(ioctl_index == INDEX_SFIXROM) ? {10'b000_0110_001, ioctl_addr[16:0]} :	// SFIX: $0620000~$063FFFF
		(ioctl_index == INDEX_P1ROM_A) ? {7'b000_0000, ioctl_addr[19:0]} :		// P1 first half or full: $0000000~$00FFFFF
		(ioctl_index == INDEX_P1ROM_B) ? {8'b000_0000_1, ioctl_addr[18:0]} :	// P1 second half: $0080000~$00FFFFF
		(ioctl_index == INDEX_P2ROM) ? 	ioctl_addr + 27'h0200000 :				// P2+: $0200000~$05FFFFF
		(ioctl_index >= INDEX_CROMS) ? 	{1'b0, ioctl_addr[24:0], 1'b0} + {ioctl_index[7:1]-INDEX_CROMS[7:1], 18'h00000, ioctl_index[0], 1'b0} + 27'h0800000 : // C*: $0800000~$1FFFFFF
		27'h0000000;

	sdram_mux SDRAM_MUX(
		.nRESET(nRESET),
		.clk_sys(clk_sys),
		
		.M68K_ADDR(M68K_ADDR), .M68K_DATA(M68K_DATA),
		.nAS(nAS), .nLDS(nLDS), .nUDS(nUDS),
		
		.SDRAM_DQ(SDRAM_DQ),
		
		.CD_TR_AREA(CD_TR_AREA),
		.CD_EXT_RD(CD_EXT_RD),
		.CD_EXT_WR(CD_EXT_WR),
		
		.DMA_ADDR_OUT(DMA_ADDR_OUT), .DMA_ADDR_IN(DMA_ADDR_IN),
		.DMA_DATA_OUT(DMA_DATA_OUT),
		.DMA_WR_OUT(DMA_WR_OUT),
		.DMA_RUNNING(DMA_RUNNING),
		.DMA_SDRAM_BUSY(DMA_SDRAM_BUSY),
		
		.CD_WR_SDRAM_SIG(CD_WR_SDRAM_SIG),
		.PCK1(PCK1), .PCK2(PCK2),
		
		.CD_BANK_SPR(CD_BANK_SPR),
		.P_BANK(P_BANK),
		.CROM_ADDR(CROM_ADDR),
		.S_LATCH(S_LATCH),
		
		.SDRAM_WR_PULSE(SDRAM_WR_PULSE),	.SDRAM_RD_PULSE(SDRAM_RD_PULSE), .SDRAM_RD_TYPE(sdram_rd_type),
		
		.SROM_DATA(SROM_DATA), .PROM_DATA(PROM_DATA), .CR_DOUBLE(CR_DOUBLE),
		.PROM_DATA_READY(PROM_DATA_READY),
		.FIX_BANK(FIX_BANK),
		
		.SPR_EN(SPR_EN), .FIX_EN(FIX_EN),
		
		.ioctl_download(ioctl_download),
		.ioctl_addr_offset(ioctl_addr_offset),
		.ioctl_dout(ioctl_dout),
		
		.nSYSTEM_G(nSYSTEM_G), .SYSTEM_CDx(SYSTEM_CDx),
		.nROMOE(nROMOE), .nPORTOE(nPORTOE), .nSROMOE(nSROMOE),
		
		.sdram_addr(sdram_addr),
		.sdram_dout(sdram_dout), .sdram_din(sdram_din),
		.wtbt(wtbt),
		.sdram_ready(sdram_ready)	//, .ready_fourth(ready_fourth)
	);
	
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
		.addr(sdram_addr[25:0]),
		.sel(~sdram_addr[26]),
		.dout(sdram1_dout),
		.din(sdram_din),
		.wtbt(wtbt),		// Always used in 16-bit mode except for CD fix data write
		.we(sdram_we),
		.rd(sdram_rd),
		.rd_type(sdram_rd_type),
		.ready(sdram1_ready)
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
		.addr(sdram_addr[25:0]),
		.sel(sdram_addr[26]),
		.dout(sdram2_dout),
		.din(sdram_din),
		.wtbt(wtbt),		// Always used in 16-bit mode except for CD fix data write
		.we(sdram_we),
		.rd(sdram_rd),
		.rd_type(sdram_rd_type),
		.ready(sdram2_ready)
	);
`else
	assign sdram2_dout = '0;
	assign sdram2_ready = 1;
`endif

	assign sdram_dout  = sdram_addr[26] ? sdram2_dout : sdram1_dout;
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
	wire nDTACK_ADJ = ~&{nSROMOE, nROMOE, nPORTOE} ? ~PROM_DATA_READY | nDTACK : nDTACK;
	
	cpu_68k M68KCPU(
		.CLK_24M(CLK_24M),
		.nRESET(nRESET),
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
	assign M68K_DATA = (nROMOE & nSROMOE & |{nPORTOE, cart_chip}) ? 16'bzzzzzzzzzzzzzzzz : PROM_DATA;
	
	// 68k work RAM
	wire [14:0] WRAM_ADDR = TRASHING ? TRASH_ADDR[14:0] : M68K_ADDR[15:1];
	wire [15:0] WRAM_DIN = TRASHING ? TRASH_ADDR[15:0] : M68K_DATA;
	
	wire WRAM_WR_L = (~nWWL | TRASHING);	// ~SYSTEM_CDx &  TESTING
	wire WRAM_WR_U = (~nWWU | TRASHING);	// ~SYSTEM_CDx &  TESTING
	
	m68k_ram WRAML(WRAM_ADDR, CLK_24M, WRAM_DIN[7:0], WRAM_WR_L, WRAML_OUT);
	m68k_ram WRAMU(WRAM_ADDR, CLK_24M, WRAM_DIN[15:8], WRAM_WR_U, WRAMU_OUT);
	
	// Work RAM or CD extended RAM read
	assign M68K_DATA[7:0] = nWRL ? 8'bzzzzzzzz : SYSTEM_CDx ? PROM_DATA[7:0] : WRAML_OUT;
	assign M68K_DATA[15:8] = nWRU ? 8'bzzzzzzzz : SYSTEM_CDx ? PROM_DATA[15:8] : WRAMU_OUT;

	
	
	// Backup RAM
	wire nBWL = nSRAMWEL | nSRAMWEN_G;
	wire nBWU = nSRAMWEU | nSRAMWEN_G;
	
	wire [15:0] sd_buff_din_sram;
	wire [14:0] sram_addr = {sd_lba[6:0], sd_buff_addr};
	// Enable writes for save file's 000000~00FFFF
	wire sram_wr = SYSTEM_MVS & ~sd_lba[7] & sd_buff_wr & sd_ack;
	
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
	wire [11:0] memcard_addr = {sd_lba[3:0], sd_buff_addr};
	wire memcard_wr = SYSTEM_CDx ? (sd_req_type == 16'h0000) & sd_buff_wr & sd_ack :		// Enable writes for save file's 000000+
							sd_lba[7] & sd_buff_wr & sd_ack;			// Enable writes for save file's 010000+
	
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
	
	// Cartridge stuff
	/*gap_hack GAPHACK(
		{C_LATCH_EXT, C_LATCH[19:4]},
		C_LATCH[3:0],
		status[29:28],
		CROM_ADDR
	);*/
	assign CROM_ADDR = {C_LATCH_EXT + 2'd1, C_LATCH, 3'b000};
	
	zmc ZMC(
		.nSDRD0(SDRD0),
		.SDA_L(SDA[1:0]), .SDA_U(SDA[15:8]),
		.MA(MA)
	);

	// Bankswitching for the PORT zone, do all games use a 1MB window ?
	// P_BANK stays at 0 for CD systems
	always @(posedge nPORTWEL or negedge nRESET)
	begin
		if (!nRESET)
			P_BANK <= 2'd0;
		else
			if (!SYSTEM_CDx) P_BANK <= M68K_DATA[1:0];
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
	
	assign M68K_DATA[7:0] = ((cart_chip == 2'd1) & ~nPORTOEL) ?
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
	
	wire [1:0] CMC_FIX_BANK;
	
	cmc_fix CMCFIX(
		.PCK2B(~PCK2),
		.PBUS(PBUS[15:0]),
		.FIXMAP_ADDR(FIXMAP_ADDR),
		.FIX_BANK(CMC_FIX_BANK)
	);
	
	// NEO-CMC handles this, set to 0 for now ()
	assign FIX_BANK = (cart_chip == 2'd3) ? CMC_FIX_BANK : 2'b00;
	
	// Fake COM MCU
	wire [15:0] COM_DOUT;
	
	com COM(
		.nRESET(nRESET),
		.CLK_24M(CLK_24M),
		.nPORTOEL(nPORTOEL), .nPORTOEU(nPORTOEU), .nPORTWEL(nPORTWEL),
		.M68K_DIN(COM_DOUT)
	);
	
	assign M68K_DATA = (cart_chip == 2'd2) ? COM_DOUT : 16'bzzzzzzzz_zzzzzzzz;
	
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
	reg [2:0] LOAD_SR;
	reg CA4_REG;
	
	// CA4's polarity depends on the tile's h-flip attribute
	// Normal: CA4 high, then low
	// Flipped: CA4 low, then high
	always @(posedge clk_sys)
	begin
		LOAD_SR <= {LOAD_SR[1:0], LOAD};
		if (LOAD_SR == 3'b011)
			CA4_REG <= CA4;
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
	
	// LO ROM address switch
	wire lo_loading = ioctl_download & (ioctl_index == INDEX_LOROM);
	wire [15:0] LO_ADDR = lo_loading ? ioctl_addr[16:1] : PBUS[15:0];
	
	lo_rom LO(LO_ADDR, ~clk_sys, ioctl_dout[7:0], lo_loading & ioctl_wr, LO_ROM_DATA);
	
	// VCS is normally used as the LO ROM's nOE but the NeoGeo relies on the fact that the LO ROM
	// will still have its output active for a short moment (~50ns) after nOE goes high
	// nPBUS_OUT_EN is used internally by LSPC2 but it's broken out here to use the additional
	// half mclk cycle it provides compared to VCS. This makes sure LO_ROM_DATA is valid when latched.
	assign PBUS[23:16] = nPBUS_OUT_EN ? LO_ROM_DATA : 8'bzzzzzzzz;
	
	fast_vram UFV(
		FAST_VRAM_ADDR,
		clk_sys,	//~CLK_24M,		// Is just CLK ok ?
		FAST_VRAM_DATA_OUT,
		~CWE,
		FAST_VRAM_DATA_IN
	);
	
	slow_vram USV(
		SLOW_VRAM_ADDR,
		clk_sys,	//~CLK_24M,		// Is just CLK ok ?
		SLOW_VRAM_DATA_OUT,
		~BWE,
		SLOW_VRAM_DATA_IN
	);
	
	wire [18:11] MA;
	wire [7:0] M1_ROM_DATA;
	wire [7:0] Z80_RAM_DATA;
	
	// M1 ROM address switch
	wire m1_loading = ioctl_download & (ioctl_index == INDEX_M1ROM);
	wire [16:0] M1_ADDR = m1_loading ? ioctl_addr[17:1] : {MA[16:11], SDA[10:0]};
	
	z80_rom M1(M1_ADDR, ~clk_sys, ioctl_dout[7:0], m1_loading & ioctl_wr, M1_ROM_DATA);
	
	z80_ram Z80RAM(SDA[10:0], CLK_4M, SDD_OUT, ~(nZRAMCS | nSDMWR), Z80_RAM_DATA);		// Fast enough ?
	
	assign SDD_IN = (~nSDZ80R) ? SDD_RD_C1 :
						(~nSDMRD & ~nSDROM) ? M1_ROM_DATA :
						(~nSDMRD & ~nZRAMCS) ? Z80_RAM_DATA :
						(~n2610CS & ~n2610RD) ? YM2610_DOUT :
						8'b00000000;
	
	wire Z80_nRESET = SYSTEM_CDx ? nRESET & CD_nRESET_Z80 : nRESET;
	
	cpu_z80 Z80CPU(
		.CLK_4M(CLK_4M),
		.nRESET(Z80_nRESET),
		.SDA(SDA), .SDD_IN(SDD_IN), .SDD_OUT(SDD_OUT),
		.nIORQ(nIORQ),	.nMREQ(nMREQ),	.nRD(nSDRD), .nWR(nSDWR),
		.nINT(nZ80INT), .nNMI(nZ80NMI)
	);
	
	wire [19:0] ADPCMA_ADDR;
	wire [3:0] ADPCMA_BANK;
	wire [23:0] ADPCMB_ADDR;
	
	/*pcm PCM(
		.CLK_68KCLKB(CLK_68KCLKB),
		.nSDROE(nSDROE
		.SDRMPX(
		.nSDPOE(nSDPOE
		.SDPMPX(
		.SDRAD(
		.SDRA_L(
		.SDRA_U(
		.SDPAD(
		.SDPA(
		.D(
		.A(
	);*/
	
	reg adpcm_wr, adpcm_rd;
	reg old_download, old_reset;
	wire adpcm_wrack, adpcm_rdack;
	
	wire pcm_loading = ioctl_download & (ioctl_index >= INDEX_VROMS) & (ioctl_index < INDEX_CROMS);
	
	// Copied from Genesis_MiSTer/Genesis.sv
	always @(posedge clk_sys)
	begin
		
		old_download <= pcm_loading;
		old_reset <= nRESET;

		if (old_reset & ~nRESET) ioctl_wait <= 0;
		
		if (old_download & ~pcm_loading)
			ioctl_wait <= 0;	// Needed ?

		if (~old_download & pcm_loading) begin
			adpcm_wr <= 0;
		end else if (pcm_loading)
		begin
			if (ioctl_wr) begin
				ioctl_wait <= 1;
				adpcm_wr <= ~adpcm_wr;
			end else if (ioctl_wait & (adpcm_wr == adpcm_wrack)) begin
				ioctl_wait <= 0;
			end
		end
	end
	
	assign DDRAM_CLK = clk_sys;
	
	// The ddram request and ack signals work on either edge
	// To trigger a read request, just set adpcm_rd to ~adpcm_rdack
	
	reg ADPCMA_READ_REQ, ADPCMB_READ_REQ;
	reg [24:0] ADPCMA_ADDR_LATCH;	// 32MB
	reg [24:0] ADPCMB_ADDR_LATCH;	// 32MB
	
	always @(posedge clk_sys) begin
		reg [1:0] ADPCMA_OE_SR;
		reg [1:0] ADPCMB_OE_SR;
		ADPCMA_OE_SR <= {ADPCMA_OE_SR[0], nSDROE};
		// Trigger ADPCM A data read on nSDROE falling edge
		if (ADPCMA_OE_SR == 2'b10) begin
			ADPCMA_READ_REQ <= ~ADPCMA_READ_REQ;
			ADPCMA_ADDR_LATCH <= {1'b0, ADPCMA_BANK, ADPCMA_ADDR};
		end
		
		// Trigger ADPCM A data read on nSDPOE falling edge
		ADPCMB_OE_SR <= {ADPCMB_OE_SR[0], nSDPOE};
		if (ADPCMB_OE_SR == 2'b10) begin
			ADPCMB_READ_REQ <= ~ADPCMB_READ_REQ;
			ADPCMB_ADDR_LATCH <= {~use_pcm, ADPCMB_ADDR};
		end
	end

	wire [7:0] ADPCMA_DATA;
	wire [7:0] ADPCMB_DATA;
	ddram DDRAM(
		.*,
		
		.wraddr(ioctl_addr[24:0] + {ioctl_index[5:0] - 6'd16, 19'h00000}),
		.din(ioctl_dout),
		.we_req(adpcm_wr),
		.we_ack(adpcm_wrack),
		
		.rdaddr(ADPCMA_ADDR_LATCH),
		.dout(ADPCMA_DATA),
		.rd_req(ADPCMA_READ_REQ),
		.rd_ack(),

		.rdaddr2(ADPCMB_ADDR_LATCH),
		.dout2(ADPCMB_DATA),
		.rd_req2(ADPCMB_READ_REQ),
		.rd_ack2()
	);

	wire [7:0] YM2610_DOUT;
	
	jt10 YM2610(
		.rst(~nRESET),
		.clk(CLK_8M), .cen(1),
		.addr(SDA[1:0]),
		.din(SDD_OUT), .dout(YM2610_DOUT),
		.cs_n(n2610CS), .wr_n(n2610WR),
		.irq_n(nZ80INT),
		.adpcma_addr(ADPCMA_ADDR), .adpcma_bank(ADPCMA_BANK), .adpcma_roe_n(nSDROE), .adpcma_data(ADPCMA_DATA),
		.adpcmb_addr(ADPCMB_ADDR), .adpcmb_roe_n(nSDPOE), .adpcmb_data(SYSTEM_CDx ? 8'h08 : ADPCMB_DATA),	// CD has no ADPCM-B
		.snd_right(snd_right), .snd_left(snd_left)
	);
	 
	 
	// For Neo CD only
	wire VIDEO_EN = SYSTEM_CDx ? CD_VIDEO_EN : 1'b1;
	wire FIX_EN = SYSTEM_CDx ? CD_FIX_EN : 1'b1;
	wire SPR_EN = SYSTEM_CDx ? CD_SPR_EN : 1'b1;
	wire DOTA_GATED = SPR_EN & DOTA;
	wire DOTB_GATED = SPR_EN & DOTB;
	wire HSync,VSync;
	
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
		.HSYNC(HSync), .VSYNC(VSync),
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
		.EN_FIX(FIX_EN)
	);
	
	pal_ram PALRAM({PALBNK, PAL_RAM_ADDR}, CLK_24M, M68K_DATA, ~nPAL_WE, PAL_RAM_DATA);	// Was CLK_12M
	
	// DAC latches
	reg ce_pix;
	always @(posedge clk_sys) begin
		reg old_clk;
	
		ce_pix <= 0;
		old_clk <= CLK_6MB;
		if(~old_clk & CLK_6MB) begin
			ce_pix <= 1;
			PAL_RAM_REG <= VIDEO_EN ? PAL_RAM_DATA : 16'h0000;
		end
	end

	assign CLK_VIDEO = clk_sys;
	assign CE_PIXEL = ce_pix;

	video_cleaner cideo_cleaner
	(
		.*,

		.clk_vid(clk_sys),
		.ce_pix(ce_pix),

		.R({PAL_RAM_REG[11:8], PAL_RAM_REG[14], {3{PAL_RAM_REG[15]}}}),
		.G({PAL_RAM_REG[7:4],  PAL_RAM_REG[13], {3{PAL_RAM_REG[15]}}}),
		.B({PAL_RAM_REG[3:0],  PAL_RAM_REG[12], {3{PAL_RAM_REG[15]}}}),

		.HSync(HSync),
		.VSync(VSync),
		.HBlank(CHBL),
		.VBlank(~nBNKB),

		.HBlank_out(),
		.VBlank_out()
	);

endmodule
