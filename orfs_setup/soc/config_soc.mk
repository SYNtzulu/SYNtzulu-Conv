# RTL_ROOT = absolute path of the repo's rtl/ directory. paths.mk is written by
# "make setup_orfs"; it is the only machine dependent piece, which is why it is
# generated and not committed.
#
# The include is relative to DESIGN_CONFIG (the variable passed to the ORFS
# flow), not to the directory make runs from: ORFS is invoked from
# $(OPENROAD_PATH)/flow, so a plain "include ../paths.mk" would look in the
# wrong place. designs/$(PLATFORM)/SYNtzulu-Conv is a symlink to this repo's
# orfs_setup/, so the path resolves back here.
include $(dir $(DESIGN_CONFIG))../paths.mk

export DESIGN_NAME     = soc
export PLATFORM        = ihp-sg13g2
export DESIGN_NICKNAME = SYNtzulu_Conv
#
# FLOW_VARIANT is the last element of the results/logs/reports path:
#     <dir>/$(PLATFORM)/$(DESIGN_NICKNAME)/$(FLOW_VARIANT)/
# so bumping it is all that is needed to keep an old run intact - variant 1
# (29 Jul, 0 DRC, WS +25.4 ns, 939 slew violations, 22668 antenna diodes)
# stays where it is and the next run lands beside it in .../2/. Do NOT change
# the nickname for this: that forks a whole new tree and loses the comparison.
#
#   1  baseline
#   2  SDC pad constraints + macro grid snapped to tracks + slew repair below
export FLOW_VARIANT    = 3

#
# rtl/define.v MUST come first: it defines EMG and CONFIG_PATH, which
# servant_syntzulu.sv needs for its `include `CONFIG_PATH.
#
# Deliberately NOT listed:
#   rtl/behavioural_ihp/*  simulation models of the RAMs; in synthesis the
#                          macros come from the lef/lib/gds below
#   std_cells/*            the platform already provides the IO cells and
#                          OPENROAD_CLKGATE (CLKGATE_MAP_FILE in the platform
#                          config.mk); those files are simulation only
export VERILOG_FILES = $(RTL_ROOT)/define.v \
                       $(RTL_ROOT)/servant/* \
                       $(RTL_ROOT)/serv/* \
                       $(RTL_ROOT)/syntzulu/* \
                       $(RTL_ROOT)/memorie_ihp/*

# servant_mux.v and servant_spi.v do `include "rtl/servant/memory_mapping.v"',
# and CONFIG_PATH is "rtl/config/emg/config.txt": both paths are relative to the
# repo root, i.e. $(RTL_ROOT)/.. , not to the directory the flow runs from.
export VERILOG_INCLUDE_DIRS = $(RTL_ROOT)/..

export SDC_FILE = $(dir $(DESIGN_CONFIG))constraint_soc.sdc

# On-chip memory macros instantiated by the design (22 macros, 3.124 mm2 of
# silicon in total):
#      1024x16 x3   servant_ram ram_lo/ram_hi, delta_modulator delta_mem
#      1024x64 x1   snn_lp weight_mem
#        64x64 x1   Syntzulu output_buffer
#   2P  512x16 x1   spike_mem_2 spike_mem
#   2P 1024x16 x16  bram_fifo potential_mem, 8 macros per layer_lp, 2 layers
#
# The two 2P (dual port) parts come from a newer IHP-Open-PDK snapshot than the
# rest of this platform - they did not exist when it was cut. Only these two
# files were copied in, everything else is untouched, so earlier runs stay
# comparable. Same LEF 5.7, same Metal1..Metal4 stack, same characterisation
# corners: they drop in. See rtl/memorie_ihp/*_ihp_*.sv for what they replaced
# and why (short version: the spike mem was 8192 flops, and the potential mem
# was six single-port 256x64 that lost a read whenever a write hit the same
# bank and moved 16 bits by activating a 64 bit row).
export ADDITIONAL_LEFS = ./platforms/ihp-sg13g2/lef/RM_IHPSG13_1P_1024x16_c2_bm_bist.lef \
                         ./platforms/ihp-sg13g2/lef/RM_IHPSG13_1P_1024x64_c2_bm_bist.lef \
                         ./platforms/ihp-sg13g2/lef/RM_IHPSG13_1P_64x64_c2_bm_bist.lef \
                         ./platforms/ihp-sg13g2/lef/RM_IHPSG13_2P_512x16_c2_bm_bist.lef \
                         ./platforms/ihp-sg13g2/lef/RM_IHPSG13_2P_1024x16_c2_bm_bist.lef

export ADDITIONAL_LIBS = ./platforms/ihp-sg13g2/lib/RM_IHPSG13_1P_1024x16_c2_bm_bist_typ_1p20V_25C.lib \
                         ./platforms/ihp-sg13g2/lib/RM_IHPSG13_1P_1024x64_c2_bm_bist_typ_1p20V_25C.lib \
                         ./platforms/ihp-sg13g2/lib/RM_IHPSG13_1P_64x64_c2_bm_bist_typ_1p20V_25C.lib \
                         ./platforms/ihp-sg13g2/lib/RM_IHPSG13_2P_512x16_c2_bm_bist_typ_1p20V_25C.lib \
                         ./platforms/ihp-sg13g2/lib/RM_IHPSG13_2P_1024x16_c2_bm_bist_typ_1p20V_25C.lib

export ADDITIONAL_GDS  = ./platforms/ihp-sg13g2/gds/RM_IHPSG13_1P_1024x16_c2_bm_bist.gds \
                         ./platforms/ihp-sg13g2/gds/RM_IHPSG13_1P_1024x64_c2_bm_bist.gds \
                         ./platforms/ihp-sg13g2/gds/RM_IHPSG13_1P_64x64_c2_bm_bist.gds \
                         ./platforms/ihp-sg13g2/gds/RM_IHPSG13_2P_512x16_c2_bm_bist.gds \
                         ./platforms/ihp-sg13g2/gds/RM_IHPSG13_2P_1024x16_c2_bm_bist.gds

# soc.v instantiates the pad ring, so yosys needs the IO liberty to blackbox
# sg13g2_IOPadIn / sg13g2_IOPadOut16mA. The platform adds the IO lef/lib/gds by
# itself, but only inside "ifdef FOOTPRINT_TCL"
# (platforms/ihp-sg13g2/config.mk:10), so this assignment is what switches them
# on. The platform is read after this file and appends with "+=", which is why
# the plain "=" above does not drop them.
export FOOTPRINT_TCL = $(dir $(DESIGN_CONFIG))pad_soc.tcl
export PDN_TCL       = $(dir $(DESIGN_CONFIG))pdn_soc.tcl

# Runs at the end of scripts/floorplan.tcl, so after FOOTPRINT_TCL has built the
# pad ring and the boundary nets exist. Stops the resizer from inserting cells
# between a pad and the chip pin - it did exactly that in variant 2, see the
# file for the evidence.
export POST_FLOORPLAN_TCL = $(dir $(DESIGN_CONFIG))pad_nets_dont_touch.tcl

# scripts/pdn.tcl sources this immediately after pdngen, so the power grid gets
# its connectivity checked at stage 2_4_floorplan_pdn instead of at the end of
# the flow, where stock ORFS does it (final_report.tcl, analyze_power_grid).
# A floating supply used to cost a full route before showing up as PSM-0069.
# SKIP_PDN_CHECK=1 downgrades the failure to a warning.
export POST_PDN_TCL  = $(dir $(DESIGN_CONFIG))../check_pdn.tcl

# ---------------------------------------------------------------------------
#  Floorplan
# ---------------------------------------------------------------------------
# CORE_AREA must be inset by exactly 285 um on every side:
#     70 bondpad band + 180 pad depth + 35 PowRingSpace = 285
# 70 and 180 are what pad_soc.tcl passes to make_io_sites, 35 is the band the
# core power ring occupies in pdn_soc.tcl. DIE_AREA is therefore CORE_AREA
# grown by 570 in x and in y. Moving one without the other either overlaps the
# ring with the core or leaves it floating.
#
# Sizing from the synthesized netlist (report_design_area on 1_synth.v gives
# 3.819 mm2 for the whole soc):
#     macros              3.124 mm2   (22 SRAMs, exact, from their LEF)
#     std cells           0.493 mm2   (3.819 - 3.124 macros - 0.202 of IO pads,
#                                      which live in the pad ring, not the core)
#     core 2660 x 2660 =  7.076 mm2   -> 51 % utilization
#
# The std cells collapsed from 1.585 mm2 to 0.493: the spike mem gave back its
# 8192 dfrbp AND the 512:1 read mux and write decoder around them, and the
# potential mem wrapper gave back the /6 and %6 dividers of the interleaved
# decode (bit slicing now). sg13g2_buf_1 went 60793 -> 7631, total cells
# 123736 -> 30800, dfrbp_1 12860 -> 4609.
#
# The core is NOT sized from the utilization ratio - it is sized from the macro
# grid below plus the fan-in margin, which is what actually binds. 51 % looks
# sparse next to the 65 % that closed before, but this design is 86 % macro by
# area and the free space is not fungible: what matters is where it is, not how
# much of it there is.
#
# THE MARGIN IS NOT DECORATION. The first attempt put the grid flush on the core
# corner (435 -> 285) with a 2450 core, and global routing died with 8161 total
# overflow at 13 % average usage. The congestion report said why: 65 % of the
# violations sat ON TOP of mac[0] and mac[4], the two macros in the bottom left,
# on tiles with capacity 0, and every violation outside the core was on the
# bottom (1483) or left (885) edge. With no gap between the core boundary and
# the first macro row, the nets coming in from the pads had no way through and
# the router tried to cross the macro obstructions. 150 um of clear channel on
# the bottom and left is what that costs.
#
# The 570 in the deltas below is the pad band: 70 bondpad + 180 pad depth + 35
# PowRingSpace on each side, see the paragraph above.
# GROWN FROM 3230/2660 IN VARIANT 3, DELIBERATELY AND TEMPORARILY.
#
# The 2660 core closed the flow in variants 1 and 2, but only just: at variant 3
# global routing failed with GRT-0116 on a single 45 um channel, and the extra
# ~1400 repair buffers had nowhere to go. Rather than trade routability against
# every other knob at once, the core goes to 3000 x 3000 so that every channel
# can be roughly tripled and the flow can be closed first.
#
#     die   3230 -> 3570   (10.43 -> 12.74 mm2, +22 %)
#     core  2660 -> 3000   ( 7.08 ->  9.00 mm2)
#     macro fraction 44 % -> 35 % of core
#
# THIS IS MEANT TO BE GIVEN BACK. Once the flow closes end to end, shrink the
# channels one at a time and watch congestion.rpt: the binding one has always
# been the top band, and 129 um is far more than the 45 that failed.
#
# The 285 inset is unchanged and must stay: 70 bondpad + 180 pad depth + 35
# PowRingSpace. DIE is therefore CORE grown by 570 in x and in y.
#
# WATCH THE PAD RING AFTER THIS CHANGE. pad_soc.tcl spreads the pads over the
# available beachfront, so a wider die moves every pad. The TopMetal2 core
# straps in pdn_soc.tcl are positioned by hardcoded offsets (180 and 500) that
# were chosen to straddle the old pad positions - see the comment there, which
# says in as many words "redo this arithmetic if DIE_AREA changes". check_pdn
# at 2_4 will catch an actual disconnection, but alignment is worth a look.
export DIE_AREA   =   0   0 3570 3570
export CORE_AREA  = 285 285 3285 3285

# Macros are placed by hand. rtl_macro_placer was tried first and ran for
# minutes without producing anything: with 17 macros in a regular pattern
# there is nothing for it to discover, and every other design with SRAMs in
# this ORFS tree (SYNtzulA, syntzulu_dual_core, syntzulu_quad_core,
# prove_augusto) sets MACRO_PLACEMENT too. Manual placement also makes the
# step deterministic and instantaneous.
#
# The layout, all R0. A 4x4 grid of potential memories fills the lower left,
# two columns per layer_lp so each core's eight macros stay together, and a band
# across the top holds everything else. The std cells get the strip to the right
# of the grid (x 2038..2735) plus the channels:
#
#   y 3044.16  output_buffer                                      (784 x 64)
#   y 2587.20  weight_mem      | ram_lo|ram_hi|delta | spike_mem
#   y 2049.60  l1 mac3 | mac7  | l2 mac3 | mac7
#   y 1512.00  l1 mac2 | mac6  | l2 mac2 | mac6    <- 4x4, column pitch 534.24,
#   y  974.40  l1 mac1 | mac5  | l2 mac1 | mac5       row pitch 537.60
#   y  436.80  l1 mac0 | mac4  | l2 mac0 | mac4
#   x          436.80  971.04  1505.28   2039.52
#
# Every channel roughly tripled when the core grew to 3000 (see DIE_AREA):
#
#     4x4 columns       47.63 -> 131.63
#     4x4 rows          95.11 -> 152.23
#     top band          45.44 -> 129.44     <- this one failed GRT-0116 at 45
#     grid to band      58.15 -> 152.23
#     band to outbuf    63.38 -> 120.50
#
# Margins left at the core edge: 842.87 um to the right of the grid (the
# standard cell strip), 432.95 to the right of the band, 176.48 above.
#
# Nothing starts before ~435 on either axis: that is the core edge at 285 plus
# the 150 um fan-in channel, see the note above DIE_AREA.
#
# EVERY COORDINATE ABOVE IS A MULTIPLE OF 3.36 um, and that is the whole reason
# they are not round numbers. make_tracks.tcl gives Metal2/Metal4 a 0.42 pitch
# and Metal1/Metal3/Metal5 a 0.48 one; 0.42 x 8 = 0.48 x 7 = 3.36 is the
# smallest common multiple, so a macro on that grid has its pins crossed by
# tracks on both layers. The old round values (435, 450, 480, 2320, 2720) were
# a multiple of neither: 435 / 0.42 = 1035.71. No macro was actually aligned,
# and the router said so 435 times in 5_1_grt.log of variant 1:
#
#     [WARNING DRT-0418] Term ...mac[3].u_ram/A_ADDR[7] has no pins on routing grid
#
# It coped - variant 1 finished at 0 DRC - by building off-grid access points,
# little oblique stubs to hook the pin and get back onto a track. Those cost
# space and are a classic source of late spacing DRCs. This is hygiene, not a
# fix for anything that was actually broken.
#
# All the SRAM signal pins sit on the bottom edge of the macro - checked on the
# 2P LEF too, Metal2 at y 0..0.5 spread over the full width - so R0 everywhere
# keeps every pin row facing down and each macro needs a channel underneath it.
# That is what sets the row pitch: 480.48 on a 385.37 tall macro leaves 95.1 um
# for the pins of the row above to escape. The column pitch 534.24 on a 402.61
# wide macro leaves 47.6 um, just over the 40 um that two facing
# MACRO_PLACE_HALO need.
#
# THE TOP BAND GAPS ARE 129.44 um, NOT ~45 LIKE THE GRID, AND THAT IS LOAD
# BEARING. At 45.44 um global routing failed outright in variant 3:
#
#     [ERROR GRT-0116] Global routing finished with congestion.
#
# and every single entry in congestion.rpt sat at x 1483..1548, y 2318..2657 -
# the channel between ram_lo and ram_hi, over the full height of both macros.
# Several tiles reported "capacity:0 usage:1", i.e. the router was trying to
# cross over ram_lo itself because the channel beside it was full.
#
# Note this was NOT a global density problem: total usage was 8.86 % and the
# overflow was 1/2/14. One 45 um channel was the whole failure.
#
# The band gaps went 45.44 -> 129.44, i.e. roughly 108 -> 308 Metal2 tracks per
# channel at the 0.42 pitch. Deliberately generous rather than incremental, to
# settle it in one run instead of three. It cost no silicon at all: the band now
# ends at 2852.05 with 92.95 um still free before the core edge at 2945, and the
# 4x4 grid below is untouched because it lives at y < 2264 and shares no space
# with the band.
#
# If you move anything here, keep it on the 3.36 grid and re-check the gaps.
# The binding one is now the 4x4 grid column pitch at 47.63 um, which has not
# caused trouble so far - if congestion ever reappears down there, that is the
# next one to widen.
#
# Two traps if you edit placement_soc.cfg:
#   - the file takes NO comments. read_macro_placement.tcl skips empty lines
#     only, anything else is parsed as an instance name.
#   - "x y" is the origin passed to odb setOrigin, which is the lower left
#     corner ONLY for R0. For R180 it is the upper right corner, for MX the
#     top left, for MY the bottom right.
#   - the instance names need their brackets escaped TWICE (bank\\[0\\]): odb
#     stores them as bank\[0\], and read_macro_placement passes the line
#     through lindex, which eats one level of backslashes.
export MACRO_PLACEMENT = $(dir $(DESIGN_CONFIG))placement_soc.cfg

# Also used as the width of the placement blockages block_channels puts around
# the macros. The platform default halo is 40 40, which the 450/480 grid pitch
# above cannot afford (two facing 40 um halos would need an 80 um gap between
# columns). 20 um is still well above what the macro power ring in pdn_soc.tcl
# needs (2.4 offset + 2 width + 0.6 spacing + 2 width = 7 um per side).
# If you widen this, widen the grid pitch in placement_soc.cfg by the same
# amount on both axes or the blockages will overlap.
export MACRO_PLACE_HALO = 20 20

# Was 0.75. The core is at 51 % utilization, so telling the placer to pack to
# 75 % local density leaves no hole where a repair buffer is actually needed -
# which is how repair_design ended up finding 644 slew violations at global
# route and inserting 1 buffer. 0.60 spreads the cells and gives it somewhere
# to land. Raise it back if global placement starts complaining about density.
export PLACE_DENSITY = 0.60

export  HOLD_SLACK_MARGIN = 0.1
export SETUP_SLACK_MARGIN = 2.5

# ---------------------------------------------------------------------------
#  Slew / cap overfixing
# ---------------------------------------------------------------------------
# BOTH OF THESE ARE PERCENTAGES, NOT FRACTIONS. scripts/util.tcl passes them to
# repair_design -slew_margin / -cap_margin, and the Tcl wrapper of that command
# sends both through rsz::parse_percent_margin_arg (check it yourself with
# "puts [info body repair_design]" in openroad). So the old CAP_MARGIN = 0.1
# asked for a 0.1 % margin - it was doing nothing at all, which is not what it
# looked like it was doing.
#
# 20 % of overfix is the headroom against the parasitics underestimate
# documented at length in post_cts_repair.tcl. Keep the two files in step.
export SLEW_MARGIN = 20
export  CAP_MARGIN = 20

# Extra repair_design pass after CTS with an explicit -max_wire_length, which
# ORFS never sets. See post_cts_repair.tcl - the reasoning is all in there.
export POST_CTS_TCL = $(dir $(DESIGN_CONFIG))post_cts_repair.tcl

# Sourced at global_route.tcl:10. Overrides repair_design_helper so the repair
# that runs on REAL routed parasitics can also split long nets - today it only
# resizes, and inserts literally zero buffers. See the file.
export PRE_GLOBAL_ROUTE = $(dir $(DESIGN_CONFIG))pre_global_route.tcl

# ---------------------------------------------------------------------------
#  Reaching scripts/resize.tcl
# ---------------------------------------------------------------------------
# The two hooks above cover CTS and global route. The third repair_design of
# the flow, at scripts/resize.tcl:24, has no hook at all - it is reached from
# platforms/ihp-sg13g2/setRC.tcl, which load.tcl:34 sources at the top of every
# stage. Both variables below are read there, inside "if defined" guards, so no
# other design on this platform is affected.

export REPAIR_HELPERS_TCL = $(dir $(DESIGN_CONFIG))repair_helpers.tcl

# Applies wherever repair_helpers.tcl's proc is in force, i.e. 3_4 and CTS.
# pre_global_route.tcl overrides it with 1000 at global route: there the length
# is the real routed one and the same number would catch far more nets.
export MAX_WIRE_LENGTH = 600

# Pre-route parasitics reference layer, default Metal2. That default is not a
# physical constant, it is a correlateRC.py fit against gcd/ibex/aes/jpeg/
# riscv32i - all standard-cell designs - and it does not transfer to a
# floorplan that is 86 % macro by area. Measured here, the routed wire is 44 %
# Metal2 / 38 % Metal3 / 17 % Metal4, a weighted 0.117 fF/um against the
# 0.0181 fF/um Metal2 implies: the estimate is 6.4x optimistic before detour
# length is counted, which is why every slew violation stays invisible until
# global route. Metal3 represents that mix.
export SIGNAL_WIRE_RC_LAYER = Metal3

# Cells that live inside the SRAM GDS but are not shipped as separate layout:
# without this the final GDS merge errors out on every SRAM.
# The 2P macros carry their own BITKIT set (RM_IHPSG13_2P_BITKIT_*), same eight
# names as the 1P one. If the merge still stops on a name not listed here, add
# it: the error message names it.
export GDS_ALLOW_EMPTY = RM_IHPSG13_1P_BITKIT_16x2_LE_con_edge_lr|RM_IHPSG13_1P_BITKIT_16x2_LE_con_tap_lr|RM_IHPSG13_1P_BITKIT_16x2_TAP_LR|RM_IHPSG13_1P_BITKIT_16x2_POWER_ramtap|RM_IHPSG13_1P_BITKIT_16x2_LE_con_corner|RM_IHPSG13_1P_BITKIT_16x2_CORNER|RM_IHPSG13_1P_BITKIT_16x2_TAP|RM_IHPSG13_1P_BITKIT_16x2_EDGE_TB|RM_IHPSG13_2P_BITKIT_16x2_LE_con_edge_lr|RM_IHPSG13_2P_BITKIT_16x2_LE_con_tap_lr|RM_IHPSG13_2P_BITKIT_16x2_TAP_LR|RM_IHPSG13_2P_BITKIT_16x2_POWER_ramtap|RM_IHPSG13_2P_BITKIT_16x2_LE_con_corner|RM_IHPSG13_2P_BITKIT_16x2_CORNER|RM_IHPSG13_2P_BITKIT_16x2_TAP|RM_IHPSG13_2P_BITKIT_16x2_EDGE_TB
