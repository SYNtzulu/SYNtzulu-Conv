##########################################################################
#  check_pdn.tcl - PDN connectivity check, right after the grid is built
##########################################################################
# WHY THIS EXISTS
#   Stock ORFS only checks the power grid in final_report.tcl, i.e. at the very
#   end of the flow, after place + CTS + route + RC extraction. So a PDN mistake
#   costs a full run (over an hour on this design) before it surfaces as
#
#       [WARNING PSM-0038] Unconnected node on net VDD at location (...)
#       [WARNING PSM-0039] Unconnected instance <macro>/VDDARRAY! at (...)
#       [ERROR   PSM-0069] Check connectivity failed on VDD.
#
#   That check needs neither the routing nor the SPEF nor the timing: the grid
#   is complete the moment pdngen returns. check_power_grid is the connectivity
#   half of analyze_power_grid without the IR drop solve, and -floorplanning
#   tells it not to complain about std cells that are not placed yet. Six
#   seconds instead of an hour.
#
#   scripts/pdn.tcl in ORFS has this same check written out and commented off
#   ("Temporarily disable due to CI issues"), so this is not a novel idea, just
#   one that upstream could not keep on by default.
#
# TWO WAYS TO RUN IT
#   1. AUTOMATICALLY, as part of the floorplan. config_soc.mk sets
#          export POST_PDN_TCL = $(dir $(DESIGN_CONFIG))../check_pdn.tcl
#      and scripts/pdn.tcl sources it immediately after pdngen. A floating
#      supply then fails stage 2_4_floorplan_pdn instead of stage 6.
#
#   2. BY HAND, on any .odb, which is how you re-check a later stage:
#          export PATH=/usr/bin:$PATH
#          openroad -no_init -exit orfs_setup/check_pdn.tcl
#          ODB=<some.odb> openroad -no_init -exit orfs_setup/check_pdn.tcl
#      Exit code is 1 if any net is floating, so it can gate a longer run.
#
#      Note on PATH: ORFS' env.sh prepends tools/install/OpenROAD/bin, which
#      does not exist in this tree - openroad and yosys come from /usr/bin.
#      Sourcing it makes every flow.sh invocation die with exit 127.
#
# WHAT IT CATCHES
#   The failure that motivated it: sram_power in pdn_soc.tcl put the TopMetal1
#   stripes of a macro where its VDDARRAY! pin is NOT, leaving the bitcell array
#   supply floating. Only short macros (the 64x64) were at risk, because they
#   get a single stripe set instead of two - see the comment in sram_power.
##########################################################################

# Sourced from pdn.tcl the design is already in memory; run standalone it is
# not, and we have to load one.
set standalone 1
if {![catch {ord::get_db_block} blk] && $blk ne "NULL"} {
    set standalone 0
}

if {$standalone} {
    set flow_results "/home/luca/OpenROAD-flow-scripts_new/flow/results/ihp-sg13g2/SYNtzulu_Conv/1"
    if {[info exists ::env(ODB)]} {
        set odb $::env(ODB)
    } else {
        set odb $flow_results/2_floorplan.odb
    }
    if {![file exists $odb]} {
        puts "check_pdn: $odb does not exist - run the floorplan first"
        exit 1
    }
    puts "check_pdn: $odb"
    read_db $odb
}

# ONLY the nets the platform declares in PWR_NETS_VOLTAGES / GND_NETS_VOLTAGES,
# which is exactly what final_report.tcl checks.
#
# Do NOT be clever and sweep every net whose sigType is POWER or GROUND: that
# also picks up the per-corner rings the pad ring creates
# (IO_CORNER_NORTH_WEST_INST.vdd_RING, .vss_RING, .iovdd_RING, .iovss_RING).
# Those are tied together by connect_by_abutment in pad_soc.tcl, not by the PDN
# grid, so PSM cannot see their continuity and reports every supply pad on them
# as floating. Four confident, wrong failures that bury the one real problem.
set voltage [dict create]
foreach var {PWR_NETS_VOLTAGES GND_NETS_VOLTAGES} {
    if {[info exists ::env($var)] && $::env($var) ne ""} {
        dict for {n v} $::env($var) { dict set voltage $n $v }
    }
}
if {![dict size $voltage]} {
    # standalone runs have no ORFS environment
    set voltage [dict create VDD 1.2 VSS 0.0]
}

set block [ord::get_db_block]
set failed {}
set checked 0
dict for {name volt} $voltage {
    set net [$block findNet $name]
    if {$net eq "NULL"} {
        puts "check_pdn: no net $name in the netlist, skipped"
        continue
    }
    incr checked
    puts "\n########## check_power_grid -net $name ##########"
    set_pdnsim_net_voltage -net $name -voltage $volt
    # -floorplanning: at this stage the std cells are not placed. Without it
    # every unplaced instance is reported as unconnected and the real problem
    # drowns in the noise.
    if {[catch {check_power_grid -net $name -floorplanning} msg]} {
        lappend failed $name
        puts "  --> $name FAILED ($msg)"
    } else {
        puts "  --> $name clean"
    }
}

puts "\n=========================================================="
if {!$checked} {
    puts "check_pdn: no POWER/GROUND net in the netlist - nothing checked"
} elseif {[llength $failed]} {
    set hint "check_pdn: floating supply on: $failed.\
              The PSM-0039 lines above name the instance and the pin whose\
              supply is not connected; that is what you fix in pdn_soc.tcl.\
              Set SKIP_PDN_CHECK=1 to run the flow anyway."
    if {$standalone} {
        puts $hint
        exit 1
    }
    if {[info exists ::env(SKIP_PDN_CHECK)] && $::env(SKIP_PDN_CHECK) ne ""} {
        utl::warn FLW 110 $hint
    } else {
        utl::error FLW 111 $hint
    }
} else {
    puts "check_pdn: all $checked supply nets are connected"
    if {$standalone} { exit 0 }
}
