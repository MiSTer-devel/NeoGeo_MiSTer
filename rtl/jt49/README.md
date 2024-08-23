# JT49 FPGA Clone of YM2149 hardware by Jose Tejada (@topapate)

You can show your appreciation through

* [Patreon](https://patreon.com/jotego), by supporting open source retro releases

YM2149 compatible Verilog core, with emphasis on FPGA implementation as part of JT12 in order to recreate the YM2203 part.

## Documentation

- [AY-3-8910 Data Manual](https://archive.org/details/AY-3-8910-8912_Feb-1979/page/n51/mode/2up)
- [AY-3-8919 Reverse Engineered](https://github.com/lvd2/ay-3-8910_reverse_engineered)
- [YM2149](https://archive.org/details/bitsavers_yamahaYM21_3070829)

## Using JT49 in a git project

If you are using JT49 in a git project, the best way to add it to your project is:

1. Optionally fork JT49's repository to your own GitHub account
2. Add it as a submodule to your git project: `git submodule add https://github.com/jotego/jt49.git`
3. Now you can refer to the RTL files in **jt49/hdl**

The advantages of a using a git submodule are:

1. Your project contains a reference to a commit of the JT49 repository
2. As long as you do not manually update the JT49 submodule, it will keep pointing to the same commit
3. Each time you make a commit in your project, it will include a pointer to the JT49 commit used. So you will always know the JT49 that worked for you
4. If JT49 is updated and you want to get the changes, simply update the submodule using git. The new JT49 commit used will be annotated in your project's next commit. So the history of your project will reflect that change too.
5. JT49 files will be intact and you will use the files without altering them.

## Usage

There are two top level files you can use:
 - **jt49_bus**: presents the expected AY-3-8910 interface
 - **jt49**: presents a simplified interface, ideal to embed. This is the one used by jt12

clk_en cannot be set to 1 for correct operation. The design assumes that there will be at least one empty clock cycle between every two clk_en high clock cycles.
 
## Files for Simulation and Synthesis

When used inside a [JTFRAME](https://github.com/jotego/jtframe) project, you can use the [yaml](hdl/jt49.yaml) file provided. If you are using this repository on its own, there is a [qip](syn/quartus/jt49.qip) for Intel Quartus available.

It is recommended to use this repository as a [git submodule](https://git-scm.com/book/en/v2/Git-Tools-Submodules) in your project.


## Port Description jt49

Name     | Direction | Width | Purpose
---------|-----------|-------|-------------------------------------
rst_n    | input     |       | active-low asynchronous reset signal
clk      | input     |       | clock
clk_en   | input     |       | clock enable. It cannot be a permanent 1
addr     | input     | 4     | selects the register to access to
cs_n     | input     |       | chip-select, active low
wr_n     | input     |       | active-low write signal
din      | input     | 8     | data to write to registers
sel      | input     |       | input clock is further divided by 2 when low
dout     | output    | 8     | data read from registers. Updated when cs_n is low
sound    | output    | 10    | Unsigned combined output of the three channels    
A        | output    | 8     | Unsigned output of channel A
B        | output    | 8     | Unsigned output of channel B
C        | output    | 8     | Unsigned output of channel C 

The module is not designed to be used at full clk speed. The clock enable input signal should divide the clock at least by two. This is needed because the volume LUT is shared for all three channels and the pipeline does not include wait states for the LUT as wait states happen naturally when clk_en is used.

The ports of **jt49_bus** replace the CPU interface with that of the original AY-3-8910.

Name     | Direction | Width | Purpose
---------|-----------|-------|-------------------------------------
rst_n    | input     |       | active-low asynchronous reset signal
clk      | input     |       | clock
clk_en   | input     |       | clock enable. It cannot be a permanent 1
bdir     | input     |       | bdir pin of AY-3-8910            
bc1      | input     |       | bc1  pin of AY-3-8910
din      | input     | 8     | data to write to registers
sel      | input     |       | input clock is further divided by 2 when low
dout     | output    | 8     | data read from registers. Updated when cs_n is low
sound    | output    | 10    | Unsigned combined output of the three channels    
A        | output    | 8     | Unsigned output of channel A
B        | output    | 8     | Unsigned output of channel B
C        | output    | 8     | Unsigned output of channel C
IOA_in   | input     | 8     | I/O port A, input side
IOA_in   | output    | 8     | I/O port A, output side
IOB_in   | input     | 8     | I/O port B, input side
IOB_in   | output    | 8     | I/O port B, output side

## Comparison with AY-3-8910 Verilog Model

A simulation test bench of jt49 vs the AY-3-8910 model (available in the doc folder via a git submodule) is available in folder ver/comp. The simulation uses a simple text file to enter arbitrary commands (test_cmd). The command file is converted to hexadecimal by parser.awk and used in simulation. The following parameters were tested:

Item                 |  Compliance      | Remarks
---------------------|------------------|-------------------------------
channel period       |  Yes             | Tested: 0, 1 and FFFF values
noise period         |  Yes             | Tested: 0, 7 and 1F values
envelope shape       |  Yes             | Tested all 16 shapes
envelope period      |  Yes             | Tested 0 and FFF values

## Resistor Load Modelling

The YM2149 was used to measure the output circuitry. According to AY-3-8910 schematics, there are 16 NMOS devices for each channel. Depending on the amplitude settings, only one of them will be active. These numbers render values that agree with the datasheet and measurements:

- Rload = 1 kOhm
- Smallest Ron = 900 Ohm (for level=15)
- Largest Roff = 3 MOhm (for level=0)
- Scale factor from one MOS to the next = 1.55

Each output level is the combination of one MOS being on and the rest off, so they combine into a single impedance, which then forms a resistor divider with the load.

The output MOS will hold its impedance even if an extra 1V is added at the load resistor (reducing the MOS headroom)

## Non Linear Effects

- Channel mixing effects by short circuiting the outputs in AY-3-8910 are not modelled
- Non linearity in YM2203 when shorting all outputs is modeled via parameter YM2203_LUMPED

Non linear effects depend on the way the chip is connected and its model. See [the connection list](doc/conn.md).

## Related Projects

Other sound chips from the same author

Chip                   | Repository
-----------------------|------------
YM2203, YM2612, YM2610 | [JT12](https://github.com/jotego/jt12)
YM2151                 | [JT51](https://github.com/jotego/jt51)
YM3526                 | [JTOPL](https://github.com/jotego/jtopl)
YM2149                 | [JT49](https://github.com/jotego/jt49)
sn76489an              | [JT89](https://github.com/jotego/jt89)
OKI 6295               | [JT6295](https://github.com/jotego/jt6295)
OKI MSM5205            | [JT5205](https://github.com/jotego/jt5205)
NEC uPN7759            | [JT7759](https://github.com/jotego/jt7759)