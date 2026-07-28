#################################################################### Design
current_design soc

#################################################################### System clock
# i_clk is the free-running clock pad. clk_gen_wb derives from it the gated
# o_clk for CPU/peripherals and the slow-tick enable for the timer, so there is
# a single clock definition at the top.
# 41.667 ns = 24 MHz, the nominal frequency of the design
# (servant.v pClockFrequency = 24_000_000). Retune together with SLOW_DIV once
# the real target frequency is fixed.
set clk_name      i_clk
set clk_port_name i_clk
set clk_period    41.667
set clk_port [get_ports $clk_port_name]
create_clock -name $clk_name -period $clk_period $clk_port

set_max_fanout 8 [current_design]
