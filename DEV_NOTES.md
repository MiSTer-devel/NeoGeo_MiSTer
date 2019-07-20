These notes were written for myself/my setup but many points could be useful for others.

# MiSTer basics
The code running on the HPS (ARM CPU) loads the requested core as an .rbf file via fpga_load_rbf in fpga_io.cpp in Main_MiSTer.

In each core, the files in /sys/ provide the common functionalities: video scaling, video and audio output, the OSD, and the HPS interface logic. The hps_io module "breaks out" a bunch of signals for the core to utilize.

The core must be held in reset and provide access to the SDRAM controller and BRAM for the HPS during ROM loading. It can then switch to run mode and start using the data itself.

To connect to the DE10 via ethernet: run `D:\OpenDHCPServer\runstandalone.bat`
**NOTE**: It may already be running as a service ! Make sure the LAN connection is enabled in the Windows network control panel. By matching its MAC address, the DE10 will be assigned IP 192.168.1.200. It's then possible to use FTP or SSH with root:1 as login.

To debug linux-side stuff (Main_MiSTer):
Putty `root:1@192.168.1.200`, `killall MiSTer` so that the binary file can be replaced, Ctrl+shift+B in VS to build, upload new binary via FTP, sync, and run `/media/fat/MiSTer`.

neogeo-lite allows for faster compilation time by omitting the HDMI scaler, it outputs 6-6-6 VGA video and stereo audio on the GPIO_1 header as follows:
```
Bottom header, pin 1 is upper right
 _39________________________________________________________01
|                                                             |
| G0 G1 G2 G3 G4 +3 G5 B3 B4 B5 VS -- -- -- +5 RA -- -- -- -- |
|                                                             |
| R0 R1 R2 R3 R4 gn R5 B2 B1 B0 HS -- -- -- gn gn -- -- -- LA |
|_____________________________________________________________|
  40                                                        02
```
Pin 10 has to be connected to ground to enable the VGA output. This is used to detect the IO extension board.

# NeoGeo core specifics

The generated .rbf is `output_files\neogeo-lite.rbf`

The ROM files are normally loaded by user_io_file_tx from user_io.cpp. For this core, neogeo_romset_tx from `/support/neogeo/loader.cpp` is used instead. 

## Save files for cartridge games

Data | Start | End
---- | ---- | ----
Backup RAM | 000000 | 00FFFF
Memory card | 010000 | 0107FF

## Save file for CD systems

Data | Start | End
---- | ---- | ----
Memory card | 000000 | 001FFF

## SDRAM multiplexing
The SDRAM extension board stores the 68k program, sprites and fix graphics.
It currently runs at 120MHz (5*24M) but may be pushed up to 144MHz (6*24M) if needed.

### 68k data
Read as soon as nSROMOE (system ROM read), nROMOE (cart ROM read) or nPORTOE (cart ROM extension read) goes low.
Right now, the 68k always runs with 1 wait cycle :(

An attempt was made to fetch 68k data 4 words at a time with burst reads, but it didn't seem to be very reliable. Try again ?

### Fix graphics
Read as soon as PCK2B rises.
Since the SDRAM provides 16-bit words and there's only an 8-bit data bus for the fix (2 pixels), one SDRAM read gives 4 pixels.
The fix data is re-organized during loading so that pixel pairs are kept adjacent in the SDRAM. This allows to do only one read for 4 pixels and use S2H1 to select which pair must be fed to NEO-B1 at the right time.

An attempt was made to fetch fix data 2 words at a time with burst reads to have the whole 8 pixel line at once. It worked but it seems better to have multiple shorter reads for more efficient SDRAM access interleave.

FIXD is latched on rising edge of CLK_1MB.

### Sprite graphics
Read as soon as PCK1B rises.
The sprite graphics data bus is 32-bit, so for one 8-pixel line, two words must be read.
The sprite data is re-organized during so that the bitplane data can be read in 4-word bursts and used as-is. The PCK1B edge is used to trigger the reads, and CA4 is used to select which 8-pixel group must be fed to NEO-ZMC2 at the right time.

CR is latched on rising edge of CLK_12M when LOAD is high.

## Loading

Fix graphics are loaded in a way that takes advantage of the 16-bit wide SDRAM data bus.

Since fix pixels are stored in pairs in columns but always read in lines, instead of storing:
`column 2 (lines 0~7), column 3 (lines 0~7), column 0 (lines 0~7), column 1 (lines 0~7)`

Load like:
`line 0 (columns 0~3), line 1 (columns 0~3)...`

Sprite graphics bytes are loaded like this:
C2 C2 C1 C1 C2 C2 C1 C1...

So bitplanes for a single line look like this:
0  1  2  3  0  1  2  3...

Complete 16-pixel line: 4*16 = 64 bits = four 16-bit SDRAM words

ioctl_index is used to tell the core where to store the data being loaded. The currently used values are:
* 0: System ROM (BIOS)
* 1: LO ROM
* 2: SFIX ROM
* 4: P1 ROM first half (or full)
* 5: P1 ROM second half
* 6: P2 ROM
* 8: S1 ROM
* 9: M1 ROM
* 16+: V ROMs, add 512kB bank number
* 64+: C ROMs, the lower 6 bits are used as a bitfield like this:
 x1BBBBBS
 B: 512kB bank number
 S: word shift (used to interleave odd/even ROMs)
 So SDRAM address = 0x0800000 + 0b1_BBBBB000_00000000_000000S0 + ioctl_addr

## romsets.xml file

* hw: Special cart chip. 0=None, 1=PRO-CT0, 2=Link MCU, 3=NEO-CMC
* pcm: 0=Game uses separate V1x and V2x ROMs, 1=Game uses PCM chip with V1, V2... ROMs
* type: P (68k program), S (fix gfx), C (sprite gfx), M (z80 program) or V (voice samples). See ROM file extension.
* offset: Where to start reading in file.
* size: How many bytes to load.
* index: Where to start writing data in SDRAM. Depends on type.
	* P: 4=First P1 half (0x000000), 5=Second P1 half (0x080000), 6=P2 (0x200000)
	* S: Always 8
	* M: Always 9
	* V: 16 + (512kB bank). Non-PCM games must have their .v1x ROMs between 16-47, and their .v2x ROMs between 48-63
	* C: 64 + (0=odd, 1=even) + (1MB bank * 2)

## BRAM zones

Memory | Size
------ | ----
68k RAM | 64kB
Z80 RAM | 2kB
Slow VRAM | 64kB
Fast VRAM | 4kB
Palette RAM | 16kB
Line buffers | 9kB
LO ROM | 64kB
M1 ROM | 128kB
Memory card | 2kB
Backup RAM | 32kB
------ | ----
Total  | 385kB

## SDRAM cart map

See [sdram_map.odg](sdram_map.odg)

Memory | Size | Start | End
------ | ---- | ----- | ---
P1 ROM | 1MB | 0000000 | 00FFFFF
P2 ROMs | 4MB | 0200000 | 05FFFFF
System ROM | 128kB | 0600000 | 061FFFF
SFIX ROM | 128kB | 0620000 | 063FFFF
Free | 256kB | 0640000 | 067FFFF
S ROM | 512kB | 0680000 | 06FFFFF
Free | 1MB | 0700000 | 07FFFFF
C ROM | 24MB | 0800000 | 1FFFFFF

Games using NEO-CMC are able to bankswitch S ROMs larger than 128kB

## SDRAM CD map

See [sdram_map.odg](sdram_map.odg)

Memory | Size | Start | End
------ | ---- | ----- | ---
P1 ROM | 1MB | 0000000 | 00FFFFF
Extended RAM | 1MB | 0100000 | 01FFFFF
Free | 4MB | 0200000 | 05FFFFF
System ROM | 512kB | 0600000 | 067FFFF
S ROM | 512kB | 0680000 | 06FFFFF
Free | 1MB | 0700000 | 07FFFFF
C ROM | 4MB | 0800000 | 0BFFFFF
Free | 20MB | 0C00000 | 1FFFFFF

## Neo CD loading notes

```
To load sectors, the Neo CD does this:
-Starts playing CD at requested MSF - 3
	MSF must be given to the LC8951 module to be copied back in the HEAD registers
	Start requesting sectors from HPS with interval timer
	Wait a bit to let the system ROM set up the IRQ masks ?
-Enables CDC interrupts
-Sets CMDIEN, DTEIEN, DECIEN and DOUTEN
-Sets DECEN, E01RQ, WRRQ, QRQ and PRQ
-Sets SYIEN, SYDEN, DSCREN, COWREN
-Waits for the CDC decoder interrupt
	Trigger the decoder interrupt (CDC_nIRQ) when the HPS has finished sending a sector
-Reads STAT3 to clear the IRQ
-Does the same thing over again (to let at least one sector go by ?)
	Need to trigger the decoder interrupt again ? Should have to do that only once per play
-At the second CDC decoder interrupt:
-Checks STAT1 to see if there aren't any error flags
-Checks STAT3 to see if the decoder status is valid
-Reads the HEAD registers, compares them with the requested MSF, if so:
-Reads the STAT registers, checks if there aren't any error flags in STAT0 and CRC OK bit
-Reads PT
	Can always be 0004 (skips sector header bytes), the Neo CD doesn't care if it changes or not
-Sets DBC to $7FF (2048-1 bytes)
-Sets DAC to PT-4
	So DAC should always be set to 0000
-Sets up LC8953 DMA to retrieve 2048 bytes
	This triggers the DMA copy from the cache to the CD sector buffer at $111204
-After copy is done, increment MFS (pulse MSF_INC)
-Decrements sector counter until 0
```

## Neo CD fix data notes

```
Normal fix data bytes:
10 18 00 08
11 19 01 09
12 1A 02 0A
13 1B 03 0B
14 1C 04 0C
15 1D 05 0D
16 1E 06 0E
17 1F 07 0F

SDRAM organization words:
10-18 00-08 11-19 01-09 12-1A 02-0A 13-1B 03-0B...

The Neo CD will write fix data as bytes so two byte writes would have to be grouped in
one SDRAM word write, but that won't work with the byte address remapping. It would require
a 32 byte buffer which would be burst written and it would be a mess...
Instead of that, just use LDQM/UDQM to do byte writes with the remapped address directly.

addr_out = ?, addr_in[...:0], ~addr_in[4], addr_in[3]
00 -> 02
01 -> 06
02 -> 0A
...
07 -> 1E

08 -> 03
09 -> 07
...

10 -> 00
11 -> 04
...

18 -> 01
19 -> 05
```
