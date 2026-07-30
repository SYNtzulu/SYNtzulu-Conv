##########################################################################
#  pdn_lab.tcl - rebuild ONLY the power grid, then measure it
##########################################################################
# Iterating on pdn_soc.tcl through "make floorplan" costs a couple of minutes
# per try. This does just the pdn stage - exactly what scripts/pdn.tcl does,
# minus the write_db - on the tapcell database the flow already produced, and
# prints the numbers that matter. About ten seconds.
#
#   export PATH=/usr/bin:$PATH
#   openroad -no_init -exit orfs_setup/pdn_lab.tcl
#
# Edit orfs_setup/soc/pdn_soc.tcl, re-run, compare. Nothing is written, so it
# cannot corrupt the flow's results.
#
# WHAT TO LOOK AT
#   "strap y" against "anello y". Today they do not overlap: the straps stop at
#   the CORE_AREA boundary and the ring sits outside it, in the PowRingSpace
#   band. They are connected only through the Metal1 std cell rails, not by the
#   TopMetal2 mesh. When a change works, the strap y range will reach into the
#   ring y range, and the via count between them stops being zero.
##########################################################################

set src /home/luca/OpenROAD-flow-scripts_new/flow/results/ihp-sg13g2/SYNtzulu_Conv/1/2_3_floorplan_tapcell.odb
if {[info exists ::env(ODB)]} { set src $::env(ODB) }
read_db $src
source /home/luca/SYNtzulu-Conv/orfs_setup/soc/pdn_soc.tcl
pdngen

set block [ord::get_db_block]
set core  [$block getCoreArea]
puts [format "\n=== CORE y %.2f .. %.2f" \
      [ord::dbu_to_microns [$core yMin]] [ord::dbu_to_microns [$core yMax]]]

foreach nn {VDD VSS} {
    set net [$block findNet $nn]
    set straps {} ; set ring {} ; set vias {}
    foreach sw [$net getSWires] {
        foreach s [$sw getWires] {
            set a [ord::dbu_to_microns [$s xMin]] ; set c [ord::dbu_to_microns [$s xMax]]
            set b [ord::dbu_to_microns [$s yMin]] ; set d [ord::dbu_to_microns [$s yMax]]
            if {[$s isVia]} { lappend vias [list $a $b $c $d] ; continue }
            set lay [[$s getTechLayer] getName]
            # a core strap is TopMetal2, tall, and tpg2Width wide (6). The ring's
            # vertical segments are also TopMetal2 and tall but pgcrWidth (10)
            # wide - that width is the only thing telling them apart.
            if {$lay eq "TopMetal2" && [expr {$d-$b}] > 1000 && [expr {$c-$a}] <= 8} {
                lappend straps [list $a $b $c $d]
            }
            if {$lay eq "TopMetal1" && [expr {$c-$a}] > 1000} {
                lappend ring [list $a $b $c $d]
            }
        }
    }
    set ys {} ; foreach r $straps { lappend ys [format "%.1f..%.1f" [lindex $r 1] [lindex $r 3]] }
    set rs {} ; foreach r $ring   { lappend rs [format "%.1f..%.1f" [lindex $r 1] [lindex $r 3]] }
    puts "=== $nn  [llength $straps] strap"
    puts "===    strap y : [join [lsort -unique $ys] "  "]"
    puts "===    anello y: [join [lsort -unique $rs] "  "]"

    # vias sitting where a strap crosses a horizontal ring segment: this is the
    # number that has to leave zero.
    set n 0
    foreach st $straps {
        lassign $st sa sb sc sd
        foreach v $vias {
            lassign $v va vb vc vd
            if {$vc <= $sa || $va >= $sc} continue
            foreach r $ring {
                lassign $r ra rb rc rd
                if {$vd > $rb && $vb < $rd} { incr n ; break }
            }
        }
    }
    puts "===    via strap<->anello: $n"
}
