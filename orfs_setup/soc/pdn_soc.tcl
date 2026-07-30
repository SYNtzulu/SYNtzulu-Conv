##########################################################################
# Global Connections
##########################################################################

# std cells
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VDD} -power
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {VSS} -ground

# rams
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VDDARRAY} -power
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VDDARRAY!} -power
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VDD!} -power
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {VSS!} -ground

# pads
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {vdd} -power
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {vss} -ground
add_global_connection -net {VDDIO} -inst_pattern {.*} -pin_pattern {iovdd} -power
add_global_connection -net {VSSIO} -inst_pattern {.*} -pin_pattern {iovss} -ground

# connection
global_connect

# voltage domains
set_voltage_domain -name {CORE} -power {VDD} -ground {VSS}
# standard cell grid and rings
define_pdn_grid -name {core_grid} -voltage_domains {CORE}

##########################################################################
##  Power settings
##########################################################################
# Core Power Ring
## Space between pads and core -> used for power ring
set PowRingSpace  35
## Spacing must meet TM2 rules
set pgcrSpacing 6
## Width must meet TM2 rules
set pgcrWidth 10
## Offset from core to power ring
set pgcrOffset [expr ($PowRingSpace - $pgcrSpacing - 2 * $pgcrWidth) / 2]

# TopMetal2 Core Power Grid
# Each PAIR straddles one north/south pad: a strap landing on the spot where a
# pad hands its supply over to the ring does not come out. With the pads that
# pad_soc.tcl places (first centre 635, pitch 280, 8 of them, 80 wide) and
# CORE_AREA starting at 285:
#     spacing = padWidth + 2*8 of clearance      = 96
#     pitch   = pad pitch                        = 280
#     offset  = 635 - tpg2Width - spacing/2 - 285 = 296
# Redo this arithmetic if DIE_AREA or the pad list change.
set tpg2Width     6
set tpg2Pitch   280
set tpg2Spacing  96
set tpg2Offset  296
set tpg2Count     8

# Macro Power Rings -> M3 and M2
## Spacing must be larger than pitch of M2/M3
set mprSpacing 0.6
## Width
set mprWidth 2
## Offset from Macro to power ring
set mprOffsetX 2.4
set mprOffsetY 0.6

# macro power grid (stripes on TopMetal1/TopMetal2 depending on orientation)
set mpgWidth 6
set mpgSpacing 4
set mpgOffset 20; # arbitrary

##########################################################################
##  SRAM power rings
##########################################################################
# offset/starts are optional and only used by the 64x64, see its call below.
proc sram_power { name macro {offset ""} {starts POWER} } {
    global mprWidth mprSpacing mprOffsetX mprOffsetY mpgWidth mpgSpacing mpgOffset
    # Macro Grid and Rings
    define_pdn_grid -macro -cells $macro -name ${name}_grid -orient "R0 R180 MY MX" \
        -grid_over_boundary -voltage_domains {CORE} \
        -halo {1 1}

    add_pdn_ring -grid ${name}_grid \
        -layer        {Metal3 Metal4} \
        -widths       "$mprWidth $mprWidth" \
        -spacings     "$mprSpacing $mprSpacing" \
        -core_offsets "$mprOffsetX $mprOffsetY" \
        -add_connect

    set sram [[ord::get_db] findMaster $macro]
    if {$sram == "NULL"} {
        utl::error PDN 1 "$macro is not instantiated in this design: update the\
                          sram_power list below to match config_soc.mk"
    }
    set sramHeight  [ord::dbu_to_microns [$sram getHeight]]
    set stripe_dist [expr $sramHeight - 2*$mpgOffset - $mpgWidth - $mpgSpacing]
    utl::report "stripe_dist of $macro: $stripe_dist"

    # for the large macros there is enough space for an additional stripe
    if {$stripe_dist > 100} {
        set stripe_dist [expr $stripe_dist/2]
    }

    # a caller-supplied offset means ONE set of stripes, positioned by hand
    if {$offset ne ""} {
        set stripe_dist $sramHeight
        set mpgOffset   $offset
    }

    add_pdn_stripe -grid ${name}_grid -layer {TopMetal1} -width $mpgWidth -spacing $mpgSpacing \
                   -pitch $stripe_dist -offset $mpgOffset -extend_to_core_ring -starts_with $starts

    # Connection of Macro Power Ring to standard-cell rails
    add_pdn_connect -grid ${name}_grid -layers {Metal3 Metal1}
    # Connection of Stripes on Macro to Macro Power Ring
    add_pdn_connect -grid ${name}_grid -layers {TopMetal1 Metal3}
    add_pdn_connect -grid ${name}_grid -layers {TopMetal1 Metal4}
    # Connection of Stripes on Macro to Core Power Stripes
    add_pdn_connect -grid ${name}_grid -layers {TopMetal2 TopMetal1}
}

add_pdn_ring -grid {core_grid} \
   -layer        {TopMetal1 TopMetal2} \
   -widths       "$pgcrWidth $pgcrWidth" \
   -spacings     "$pgcrSpacing $pgcrSpacing" \
   -pad_offsets  "6 6" \
   -add_connect                        \
   -connect_to_pads                    \
   -connect_to_pad_layers TopMetal2

# M1 Standardcell Rows (tracks)
add_pdn_stripe -grid {core_grid} -layer {Metal1} -width {0.44} -offset {0} \
               -followpins -extend_to_core_ring

# SRAMS - this list must match the macros instantiated in config_soc.mk
sram_power "grid_1024x16"    "RM_IHPSG13_1P_1024x16_c2_bm_bist"
sram_power "grid_wmem"       "RM_IHPSG13_1P_1024x64_c2_bm_bist"
sram_power "grid_2p_512x16"  "RM_IHPSG13_2P_512x16_c2_bm_bist"
sram_power "grid_2p_1024x16" "RM_IHPSG13_2P_1024x16_c2_bm_bist"

# The 64x64 is only 64.36 um tall: two stripe sets do not fit, and the one set
# has to land ON the VDDARRAY! pin, whose Metal4 fingers run from y 45.465 up to
# the top of the macro. Miss it and the bitcell array supply is left floating -
# the flow then dies at the very end with PSM-0069.
#   -offset is the CENTRE of the first stripe. With -starts_with GROUND the
#   POWER one lands 10 um above it: 44.91 + 10 = 54.91, metal at 51.91..57.91,
#   inside the pin. POWER first would push GROUND past the macro boundary.
sram_power "grid_64x64" "RM_IHPSG13_1P_64x64_c2_bm_bist" 44.91 GROUND

# Top power grid
# Top 2 Stripe
add_pdn_stripe -grid {core_grid} \
               -layer {TopMetal2}  \
               -width $tpg2Width \
               -pitch $tpg2Pitch  \
               -spacing 75  \
               -offset 180 \
               -extend_to_core_ring \
               -snap_to_grid \
               -number_of_straps 1
               
# Top 2 Stripe
add_pdn_stripe -grid {core_grid} \
               -layer {TopMetal2}  \
               -width $tpg2Width \
               -pitch $tpg2Pitch  \
               -spacing 75  \
               -offset 500 \
               -extend_to_core_ring \
               -snap_to_grid \
               -number_of_straps 2


# "The add_pdn_connect command is used to define which layers in the power grid are to be connected together.
#  During power grid generation, vias will be added for overlapping power nets and overlapping ground nets."
# M1 is declared vertical but tracks still horizontal
# vertical TopMetal2 to below horizonals (M1 has horizontal power tracks)
add_pdn_connect -grid {core_grid} -layers {TopMetal2 Metal1}
add_pdn_connect -grid {core_grid} -layers {TopMetal2 Metal2}
add_pdn_connect -grid {core_grid} -layers {TopMetal2 Metal4}
# power ring to standard cell rails
add_pdn_connect -grid {core_grid} -layers {Metal3 Metal1}
add_pdn_connect -grid {core_grid} -layers {Metal3 Metal2}
