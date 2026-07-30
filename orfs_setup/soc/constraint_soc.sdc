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

# This line CANNOT loosen the limit, only tighten it, so do not bother trying.
# sg13g2_stdcell_typ_1p20V_25C.lib:34 declares default_max_fanout : 8 and STA
# applies whichever of the two is tighter. Raising this to 16 was tried in
# variant 2 and changed nothing: the CTS report still came back with "Limit 8".
#
# Which also means the 366 fanout violations of variant 1 were never this
# line's fault. They are the library limit meeting the antenna diodes that
# repair_antennas hangs on a net after the resizer has finished - wire3/X ended
# up at 398. Fix the diodes, not the constraint.
# set_max_fanout 8 [current_design]

#################################################################### Pad boundary
# soc.v instantiates the pad ring itself, so the top level ports ARE the
# bondpad side: everything below describes the world OUTSIDE the chip, and the
# pad delay is already modelled by the liberty in between.
#
# Without these two lines STA assumes a 0 ns edge and a 0 pF load at every pad,
# which is not a pessimistic default, it is an impossible one - and it means
# the I/O paths are not analysed at all rather than analysed optimistically.

# sg13g2_IOPadIn is characterised for input slews of 0.12 .. 3.5 ns
# (index_1 of its delay arcs). The implicit 0.00 is below the first table
# point, so today every input, i_clk included, is extrapolated off the end of
# the characterisation. 1.0 ns is a plausible board level edge and sits mid
# table; tighten it for i_clk, which comes off a crystal/oscillator.
#
# Note the order: OpenSTA has no remove_from_collection, so the blanket value
# goes on first and i_clk overrides it on the next line. Do not swap them.
set_input_transition 1.0 [all_inputs]
set_input_transition 0.5 [get_ports i_clk]

# sg13g2_IOPadOut16mA declares max_capacitance 4.21305 pF on its pad pin
# (capacitive_load_unit is 1 pF), while its delay tables run out to 15 pF.
# 4.0 stays just inside the vendor limit.
#
# WATCH THIS ONE: bondwire + package pin + PCB trace + receiver is typically
# 5..15 pF, so 4.21 pF is a tight budget for a real package. If the packaging
# plan lands above it, this pad is out of spec and it has to be known now, not
# after tapeout. Replace 4.0 with the number from the package model.
set_load 4.0 [all_outputs]

#################################################################### Asynchronous
# buttons and the UART have no phase relationship with i_clk - they are
# synchronised or oversampled inside the design - so there is no real path to
# constrain. i_rxd is listed for the day RICEZIONE is turned back on; today
# its pad is physical only (see pad_soc.tcl) and the port has no core side.
#
# buttons and led are buses: the netlist carries buttons[0]..[2] and led[0]..[3]
# as separate ports, so the bare name matches nothing and the pattern is needed.
set_false_path -from [get_ports buttons[*]]
set_false_path -to   [get_ports {o_txd led[*]}]

#################################################################### SPI flash
# o_flash_sck is not a port that happens to toggle, it is a generated clock:
# the FSM in spi_master_asic.v drives SPI_SCK low on counter_clk == 0 and high
# on counter_clk >= 1, with the counter reloading each time - an exact
# divide-by-2 of i_clk, so 12 MHz. Without this declaration nothing on the
# flash interface is constrained.
create_generated_clock -name flash_sck -source [get_ports i_clk] \
                       -divide_by 2 [get_ports o_flash_sck]

# TODO - THESE FOUR NUMBERS ARE PLACEHOLDERS, they are not derived from
# anything. Replace them from the datasheet of the flash that will actually be
# mounted, plus ~6 ps/mm of PCB flight time:
#     set_output_delay -max =  tSU(flash)   + flight
#     set_output_delay -min = -tHD(flash)   + flight
#     set_input_delay  -max =  tCLQV(flash) + flight
#     set_input_delay  -min =  tCLQX(flash) + flight
# The values below are ballpark for a generic SPI NOR and are here only so the
# paths get analysed instead of silently ignored.
#
# Note that -min 0.0 is the harshest hold requirement that can be written: the
# real tHD is positive, so the real -min is NEGATIVE and much easier to meet.
# The 0.0 below is what made CTS hold repair go to work on these two ports in
# variant 2 - see pad_nets_dont_touch.tcl for where it put the delay cells.
set_output_delay -clock flash_sck -max  5.0 [get_ports {o_flash_ss o_flash_mosi}]
set_output_delay -clock flash_sck -min  0.0 [get_ports {o_flash_ss o_flash_mosi}]
set_input_delay  -clock flash_sck -max  8.0 [get_ports i_flash_miso]
set_input_delay  -clock flash_sck -min  0.0 [get_ports i_flash_miso]

#################################################################### SRAM byte mask
# THIS IS A WORKAROUND, NOT A REAL CONSTRAINT. It exists to force an optimiser
# to do something it should have done on its own. Read this before touching it.
#
# In variant 2 the worst slew in the whole design sits on the byte-mask bus of
# weight_mem, measured at global route with real parasitics:
#
#     ...weight_mem_i.u_ram/A_BM[63]   limit 0.48   slew 19.05   (VIOLATED)
#     ...weight_mem_i.u_ram/A_BM[62]   limit 0.48   slew 14.29
#     ...weight_mem_i.u_ram/A_BM[61]   limit 0.48   slew 10.72   ... and so on
#
# A perfect x1.33 geometric progression, which is the signature of a
# distributed RC line: one driver at one end, taps along the way, the far end
# worst. All eight bits are the SAME net, wr_bm[48], driven by _49993_ - a
# sg13g2_inv_1, the smallest inverter in the library - into 16 macro pins.
# It is also exactly the "max fanout 16 vs limit 8" violator that the reports
# had been flagging all along.
#
# The numbers say this is not a hard problem: 540 um of HPWL, and the 16 macro
# pins are 0.00286 pF each, so 0.046 pF of pin load in total. A sg13g2_inv_16
# is rated for 4.8 pF. Upsizing that one cell should end the whole thing.
#
# repair_design does not do it, and I do not know why. Ruled out so far:
#   - MATCH_CELL_FOOTPRINT: every sg13g2 inverter shares cell_footprint "IN",
#     so inv_1 -> inv_16 is a legal swap for the resizer.
#   - antenna diodes: this net has zero of them.
# Left open: repair_design at global_route.tcl:57 may simply be looking at the
# net before the incremental re-routes and jumper insertion that follow it,
# and therefore seeing a much milder version than the one measured above.
#
# WHY set_max_delay AND NOT set_max_transition. Two reasons, both checked:
#   - OpenSTA rejects pins for set_max_transition and set_max_capacitance
#     ("[ERROR STA-0100] unsupported object type Pin"), so the DRV limit on a
#     macro input pin cannot be tightened from SDC at all.
#   - It would not have helped anyway. The limit is already 0.476 ns against a
#     reality of 19 ns: the tool knows and does not act. Tightening a limit
#     that is already blown 40x over changes nothing.
# set_max_delay instead hands the net to a DIFFERENT optimiser. Slew is
# repair_design's job; a max_delay violation is repair_timing's. With +25 ns
# of slack on a 41.667 ns period, repair_timing currently has no reason to
# touch anything anywhere in this design. This gives it one.
#
# On the value: 5.0 ns is comfortably reachable with a decent driver (~0.5 ns)
# and far below the ~19 ns of today, so the resizer gets a clear, achievable
# target. Do NOT tighten it towards 1 ns - an unreachable constraint makes the
# resizer churn without converging.
#
# On the scope: deliberately only weight_mem's A_BM. Applying this to every
# input pin of all 22 macros would constrain thousands of paths and slow STA
# down badly, to cure two nets. Widen it only if this works.
#
# The wildcard has to be iterated: passing the whole collection to -to fails
# with STA-0100, one pin at a time is accepted.
# DISABLED, and probably for good. This was written before the cause was
# understood, and it treats the symptom: it does not make the net any better,
# it just bribes a second optimiser into carrying the first one's work.
#
# The cause turned out to be in the flow, not in the constraints. At global
# route repair_design reported 734 slew violations and inserted ZERO buffers,
# because ORFS never passes -max_wire_length and OpenROAD's own default is
# 23868 um on a 3230 um die - so no net ever counts as long, and the only
# repair that helps a wire-RC-dominated net is switched off. That is fixed
# properly in pre_global_route.tcl.
#
# Kept here, disabled, because the reasoning above is worth having if the
# proper fix ever falls short. Re-enable by uncommenting the loop - but only
# one change at a time, or the next run tells you nothing.
#
# foreach pin [get_pins {*weight_mem_i.u_ram/A_BM[*]}] {
#     set_max_delay 5.0 -to $pin
# }
