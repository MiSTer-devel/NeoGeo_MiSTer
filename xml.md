
# Advanced ROM Options

### Example MAME style rom entry
Below is an example of an XML entry for a MAME style ROM set.

    <romset  name="aof" pcm="1" altname="Art of Fighting">
	    <file  name="044-p1.p1" type="P"  index="4"  offset="0"/>
	    <file  name="044-s1.s1" type="S"  index="8"  offset="0"/>
	    <file  name="044-c1.c1" type="C"  index="64"  offset="0"/>
	    <file  name="044-c2.c2" type="C"  index="65"  offset="0"/>
	    <file  name="044-c1.c1" type="C"  index="72"  offset="0x100000"/>
	    <file  name="044-c2.c2" type="C"  index="73"  offset="0x100000"/>
	    <file  name="044-c3.c3" type="C"  index="68"  offset="0"/>
	    <file  name="044-c4.c4" type="C"  index="69"  offset="0"/>
	    <file  name="044-c3.c3" type="C"  index="76"  offset="0x100000"/>
	    <file  name="044-c4.c4" type="C"  index="77"  offset="0x100000"/>
	    <file  name="044-m1.m1" type="M"  index="9"  offset="0"/>
	    <file  name="044-v2.v2" type="V"  index="16"  offset="0"/>
	    <file  name="044-v4.v4" type="V"  index="20"  offset="0"/>
    </romset>

#### Header Fields
|Field|Use|
|--|--|
|name|Specifies the folder or zip name of the ROM set. This may have multiple entries, separated by commas.|
|altname|The human readable name of the game.|
|pcm|Indicates that the game uses a PCM combination chip.|
|ct0|Indicates the presence of CT0 chip if 1.|
|sma|Indicates the presence of SMA chip. Valid values are 1 to 5.|
|pvc|Indicates the presence of PVC chip if 1.|
|cmc|Indicates the presence of CMC chip. Valid values are 1 to 2.|
|link|Indicates the presence of Link chip if 1.|
|rom_wait|1 wait cycle for ROM zone if 1.|
|p_wait|Wait cycles for PORT zone. Valid values are 1 to 2.|

#### File Fields
|Field|Use|
|--|--|
|name|Specifies the name of the file|
|type|Specifies the file's ROM type (optional)|
|index|Memory position into which to load the file. See below for more information.|
|offset|Offset in file to load from (0 if absent).|
|size|Size of data to load (whole file if absent)|

##### Indexes
Indexes are determines by file types and the size of files being loaded.
|ROM type| Possible index(es)|
|--|--|
| P | 4 for P1(or P1A) ROM or merged P ROM, 5 - P1B ROM, 6 - P2 ROM
| S | 8
| M | 9
| V | 16-47 for A part, 48-63 for B part. 512KB chunks
| C | 15 for merged C ROM (Darksoft), 64-255 for unmerged ROM (MAME) LSB is low/high word. 512KB chunks.

### Example Darksoft Entry

    <romset  name="bjourney"  pcm="0"  altname="Blues Journey" vromb_offset="0x200000"  vrom_mirror="0"/>

#### Header Fields
The header fields are mostly the same as MAME entries, with two additions:
|Field|Use|
|--|--|
|vromb_offset|Specifies the offset in file for the second V ROM entry.|
|vrom_mirror|Specifies if the V ROM file should use address mirroring (enabled by default).|

## Zips
ZIP files are treated as folders and may include either single game or multiple

## romsets.xml
romsets.xml must be placed in the main NeoGeo directory. Each sub-folder may include its own romsets.xml which replaces the parent romsets.xml.

## romset.xml
romset.xml is a single entry from romsets.xml. If this file is found then current folder it treated as a single game folder (all subfolders will be ignored).
