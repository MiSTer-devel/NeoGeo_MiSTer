# JT12 FPGA Clone of Yamaha OPN hardware by Jose Tejada (@topapate)
===================================================================

You can show your appreciation through
* [Patreon](https://patreon.com/jotego), by supporting releases
* [Paypal](https://paypal.me/topapate), with a donation


JT12 is an FM sound source written in Verilog, fully compatible with YM2612/YM3438 (Megadrive), YM2610 (NeoGeo) and YM2203 (PC88, arcades).

The implementation tries to be as close to original hardware as possible. Low usage of FPGA resources has also been a design goal. Except in the operator section (jt12_op) where an exact replica of the original circuit is done. This could be done in less space with a different style but because this piece of the circuit was reversed engineered by Sauraen, I decided to use that knowledge.

## Using JT12 in a git project

If you are using JT12 in a git project, the best way to add it to your project is:

1. Optionally fork JT12's repository to your own GitHub account
2. Add it as a submodule to your git project: `git submodule add https://github.com/jotego/jt12.git`
3. Now you can refer to the RTL files in **jt12/hdl**

The advantages of a using a git submodule are:

1. Your project contains a reference to a commit of the JT12 repository
2. As long as you do not manually update the JT12 submodule, it will keep pointing to the same commit
3. Each time you make a commit in your project, it will include a pointer to the JT12 commit used. So you will always know the JT12 that worked for you
4. If JT12 is updated and you want to get the changes, simply update the submodule using git. The new JT12 commit used will be annotated in your project's next commit. So the history of your project will reflect that change too.
5. JT12 files will be intact and you will use the files without altering them.

## Directories

* hdl -> all relevant RTL files, written in verilog
* ver -> test benches
* ver/verilator -> test bench that can play vgm files

## Usage

Chip    | Top Level     | QIP File
--------|---------------|---------
YM2610  |   jt10.v      | jt10.qip
YM2612  |   jt12.v      | jt12.qip
YM2203  |   jt03.v      | jt03.qip

## Simulation

There are several simulation test benches in the **ver** folder. The most important one is in the **ver/verilator** folder. The simulation script is called with the shell script **go** in the same folder. The script will compile the file **test.cpp** together with other files and the design and will simulate the tune specificied with the -f command. It can read **vgm** tunes and generate .wav output of them.

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