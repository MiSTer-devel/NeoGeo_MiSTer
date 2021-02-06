
# [SNK Neo Geo](https://en.wikipedia.org/wiki/Neo_Geo_(system)) for [MiSTer Platform](https://github.com/MiSTer-devel/Main_MiSTer/wiki) 

This is an FPGA implementation of the NEO GEO/MVS system by [Furrtek](https://www.patreon.com/furrtek/posts)

## Features
* Supports memory card saving
* MVS and AES system support
* Compatible with Darksoft ROM sets using provided XML
* Compatible with decrypted MAME ROM sets using your own XML
* Compatible with decrypted .neo ROM sets
* Compatible with gog.com ROMs using provided XML
* Support for Universe BIOS

Note: Core doesn't support encrypted ROMs. Make sure the ROM has no encrypted parts before use. MAME ROM pack includes many encrypted ROMs so it's not recommended for inexperienced users. Using the .neo conversion tool with a MAME ROM set will result in some ROMs still being encrypted. There is an alternate .neo conversion tool for the Darksoft ROM set that will give you a fully decrypted set.

[MAME to .neo conversion tool](https://github.com/city41/neosdconv)

[Darksoft to .neo conversion tool](https://gitlab.com/loic.petit/darksoft-to-neosd/)

## Installation
Copy the NeoGeo_\*.rbf file to the 'Console' or 'Arcade' folder (your choice) on the SD card. ROMS should go in the 'games\NeoGeo' folder. For ease of use, it is strongly suggested that people use the Darksoft ROM pack. These can be either zipped or unzipped with minimal loading speed difference. Several things must be observed:
* When using an unzipped Darksoft ROM set, each game's ROM files must be in their own folder and the folders containing the ROM sets must be named to match the XML (MAME standard names)
* ROMs can be placed inside sub-folders for organization
* Zipped ROMs must **not** contain folders.

In addition, several bios files must be placed in the 'games\NeoGeo' folder for the core to function properly:
* 000-lo.lo
* sfix.sfix
* sp-s2.sp1 (MVS)
* neo-epo.sp1 (AES)
* uni-bios.rom

Sometimes these files may be named slightly different depending on where they are obtained, but they must be renamed to match the filenames above to work with MiSTer. You may choose between using original system BIOS (sp-s2.sp1/neo-epo.sp1) and uni-bios.rom. Using uni-bios is recommended, and can be obtained [here](http://unibios.free.fr/).

Lastly, **romsets.xml** from the release folder must also be placed in the directory. The provided XML is for Darksoft ROMs only, you must make your own for MAME ROMs. This file describes to the core where the ROM sets are located and how to load them. **gog-romsets.xml** can be used (renamed to **romsets.xml**) for games purchased from gog.com (which also include all the needed bios files), see comments in gog-romsets.xml .

## Saving and Loading
In AES mode, all saves are to the memory card only. In MVS mode, some games and uni-bios save their settings to a special area of battery backed ram built into the system, while game data can be still be saved to a memory card. To simplify things, it is suggested to stick to one system type on the OSD and use uni-bios to change the system type, so that game information is saved consistently.

## RAM and Game Sizes
Neo Geo uses very large ROMs. About 84% of the library will fit onto a 32 megabyte SDRAM module. Another 12% will fit onto a 64 megabyte SDRAM module. The remaining 8 games require a 128 megabyte module. For more information about which games can be loaded with which sized RAM, open romsets.xml in your favorite text editor or github. The games are organized by size.
