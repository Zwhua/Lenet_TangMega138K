# Timing Constraints for lenet_V003 project
# Generated to handle asynchronous clock domains

# Define primary input clock (25 MHz board clock)
create_clock -name clk_in -period 40.0 [get_ports {clk_in}]

# Define PLL output clock (CLKOUT0, configured for ~19.23 MHz)
# Period = 1000/19.23 ≈ 52.0 ns
create_clock -name pll_clk -period 52.0 [get_nets {hfextclk}]

# Define JTAG TCK clock (typically 10-50 MHz, assume 10 MHz conservatively)
create_clock -name tck -period 100.0 [get_ports {tck}]

# Define RTC clock (low frequency, 32.552 kHz)
# Period = 1000000/32.552 ≈ 30720 ns
create_clock -name lfextclk -period 30720.0 [get_nets {lfextclk}]

# Set asynchronous clock groups - Group 1: Main system clock from PLL - Group 2: JTAG clock (TCK) - Group 3: RTC low-frequency clock
set_clock_groups -asynchronous -group [get_clocks {pll_clk clk_in}] -group [get_clocks {tck}] -group [get_clocks {lfextclk}]

# False paths between asynchronous clock domains (redundant with clock_groups, but explicit)
set_false_path -from [get_clocks {tck}] -to [get_clocks {pll_clk}]
set_false_path -from [get_clocks {pll_clk}] -to [get_clocks {tck}]
set_false_path -from [get_clocks {lfextclk}] -to [get_clocks {pll_clk}]
set_false_path -from [get_clocks {pll_clk}] -to [get_clocks {lfextclk}]
set_false_path -from [get_clocks {tck}] -to [get_clocks {lfextclk}]
set_false_path -from [get_clocks {lfextclk}] -to [get_clocks {tck}]

# Input/Output delays (adjust as needed based on board constraints)
# set_input_delay -clock pll_clk -max 5.0 [get_ports {input_ports}]
# set_output_delay -clock pll_clk -max 5.0 [get_ports {output_ports}]
