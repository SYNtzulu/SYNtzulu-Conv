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

# On-chip memory macros instantiated by the design:
#   1024x16 x3  servant_ram -> ihp_ram (lo/hi), delta_modulator_multichannel
#    256x64 x2  bram_fifo -> IHP3_singlePort_readFirst, one per layer_lp
#   1024x64 x1  snn_lp -> weight_mem_ihp_1024x64
#     64x64 x1  Syntzulu -> ihp_ram_64x64
export ADDITIONAL_LEFS = ./platforms/ihp-sg13g2/lef/RM_IHPSG13_1P_1024x16_c2_bm_bist.lef \
                         ./platforms/ihp-sg13g2/lef/RM_IHPSG13_1P_1024x64_c2_bm_bist.lef \
                         ./platforms/ihp-sg13g2/lef/RM_IHPSG13_1P_256x64_c2_bm_bist.lef \
                         ./platforms/ihp-sg13g2/lef/RM_IHPSG13_1P_64x64_c2_bm_bist.lef

export ADDITIONAL_LIBS = ./platforms/ihp-sg13g2/lib/RM_IHPSG13_1P_1024x16_c2_bm_bist_typ_1p20V_25C.lib \
                         ./platforms/ihp-sg13g2/lib/RM_IHPSG13_1P_1024x64_c2_bm_bist_typ_1p20V_25C.lib \
                         ./platforms/ihp-sg13g2/lib/RM_IHPSG13_1P_256x64_c2_bm_bist_typ_1p20V_25C.lib \
                         ./platforms/ihp-sg13g2/lib/RM_IHPSG13_1P_64x64_c2_bm_bist_typ_1p20V_25C.lib

export ADDITIONAL_GDS  = ./platforms/ihp-sg13g2/gds/RM_IHPSG13_1P_1024x16_c2_bm_bist.gds \
                         ./platforms/ihp-sg13g2/gds/RM_IHPSG13_1P_1024x64_c2_bm_bist.gds \
                         ./platforms/ihp-sg13g2/gds/RM_IHPSG13_1P_256x64_c2_bm_bist.gds \
                         ./platforms/ihp-sg13g2/gds/RM_IHPSG13_1P_64x64_c2_bm_bist.gds

# soc.v instantiates the pad ring, so yosys needs the IO liberty to blackbox
# sg13g2_IOPadIn / sg13g2_IOPadOut16mA. The platform adds the IO lef/lib/gds by
# itself, but only inside "ifdef FOOTPRINT_TCL"
# (platforms/ihp-sg13g2/config.mk:10), so this assignment is what switches them
# on. The platform is read after this file and appends with "+=", which is why
# the plain "=" above does not drop them.
#
# pad_soc.tcl does not exist yet: FOOTPRINT_TCL is only consumed at the
# floorplan stage, so synthesis runs without it. Write the pad placement script
# before going past synth.
export FOOTPRINT_TCL = $(dir $(DESIGN_CONFIG))pad_soc.tcl

# Floorplan onwards (DIE_AREA, CORE_AREA, MACRO_PLACEMENT, PDN_TCL) is not set
# up yet: this config covers synthesis only.
