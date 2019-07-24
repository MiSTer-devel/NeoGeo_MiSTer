derive_pll_clocks
derive_clock_uncertainty

# Specify PLL-generated clock(s)
create_generated_clock -source [get_pins -compatibility_mode {*|pll|pll_inst|altera_pll_i|*[2].*|divclk}] \
                       -name SDRAM2_CLK [get_ports {SDRAM2_CLK}]

# Set acceptable delays for SDRAM2 chip (See correspondent chip datasheet) 
set_input_delay -max -clock SDRAM2_CLK 6.4ns [get_ports SDRAM2_DQ[*]]
set_input_delay -min -clock SDRAM2_CLK 3.7ns [get_ports SDRAM2_DQ[*]]
set_output_delay -max -clock SDRAM2_CLK 1.6ns [get_ports {SDRAM2_D* SDRAM2_A* SDRAM2_BA* SDRAM2_n*}]
set_output_delay -min -clock SDRAM2_CLK -0.9ns [get_ports {SDRAM2_D* SDRAM2_A* SDRAM2_BA* SDRAM2_n*}]
