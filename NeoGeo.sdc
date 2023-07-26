derive_pll_clocks
derive_clock_uncertainty

set_false_path -from {emu|cfg[*]}

set_multicycle_path -from {emu|Z80CPU|*} -setup 2
set_multicycle_path -from {emu|Z80CPU|*} -hold 1
