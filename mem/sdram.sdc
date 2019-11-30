derive_pll_clocks
derive_clock_uncertainty

set clk_sdram_sys  {*|pll|pll_inst|altera_pll_i|*[0].*|divclk}
set_input_delay  -clock $clk_sdram_sys  9ns [get_ports SDRAM_DQ[*]]
set_output_delay -source_latency_included -clock $clk_sdram_sys -3ns [get_ports {SDRAM_D* SDRAM_A* SDRAM_BA* SDRAM_n* SDRAM_CKE}]
