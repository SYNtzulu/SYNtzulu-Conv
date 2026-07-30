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
export FLOW_VARIANT    = 1

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
export DIE_AREA   =   0   0 3230 3230
export CORE_AREA  = 285 285 2945 2945

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
#   y 2720   output_buffer                                        (784 x 64)
#   y 2320   weight_mem      | ram_lo|ram_hi|delta | spike_mem
#   y 1875   l1 mac3 | mac7  | l2 mac3 | mac7
#   y 1395   l1 mac2 | mac6  | l2 mac2 | mac6      <- 4x4, column pitch 450,
#   y  915   l1 mac1 | mac5  | l2 mac1 | mac5         row pitch 480
#   y  435   l1 mac0 | mac4  | l2 mac0 | mac4
#   x         435     885     1335      1785
#
# Nothing starts before 435 on either axis: that is the core edge at 285 plus
# the 150 um fan-in channel, see the note above DIE_AREA.
#
# All the SRAM signal pins sit on the bottom edge of the macro - checked on the
# 2P LEF too, Metal2 at y 0..0.5 spread over the full width - so R0 everywhere
# keeps every pin row facing down and each macro needs a channel underneath it.
# That is what sets the row pitch: 480 on a 385.37 tall macro leaves 94.6 um for
# the pins of the row above to escape. The column pitch 450 on a 402.61 wide
# macro leaves 47.4 um, just over the 40 um that two facing MACRO_PLACE_HALO
# need. Every gap in the block above is >= 43 um for the same reason.
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

export PLACE_DENSITY = 0.75

export  HOLD_SLACK_MARGIN = 0.1
export SETUP_SLACK_MARGIN = 2.5

export CAP_MARGIN = 0.1

# Cells that live inside the SRAM GDS but are not shipped as separate layout:
# without this the final GDS merge errors out on every SRAM.
# The 2P macros carry their own BITKIT set (RM_IHPSG13_2P_BITKIT_*), same eight
# names as the 1P one. If the merge still stops on a name not listed here, add
# it: the error message names it.
export GDS_ALLOW_EMPTY = RM_IHPSG13_1P_BITKIT_16x2_LE_con_edge_lr|RM_IHPSG13_1P_BITKIT_16x2_LE_con_tap_lr|RM_IHPSG13_1P_BITKIT_16x2_TAP_LR|RM_IHPSG13_1P_BITKIT_16x2_POWER_ramtap|RM_IHPSG13_1P_BITKIT_16x2_LE_con_corner|RM_IHPSG13_1P_BITKIT_16x2_CORNER|RM_IHPSG13_1P_BITKIT_16x2_TAP|RM_IHPSG13_1P_BITKIT_16x2_EDGE_TB|RM_IHPSG13_2P_BITKIT_16x2_LE_con_edge_lr|RM_IHPSG13_2P_BITKIT_16x2_LE_con_tap_lr|RM_IHPSG13_2P_BITKIT_16x2_TAP_LR|RM_IHPSG13_2P_BITKIT_16x2_POWER_ramtap|RM_IHPSG13_2P_BITKIT_16x2_LE_con_corner|RM_IHPSG13_2P_BITKIT_16x2_CORNER|RM_IHPSG13_2P_BITKIT_16x2_TAP|RM_IHPSG13_2P_BITKIT_16x2_EDGE_TB
