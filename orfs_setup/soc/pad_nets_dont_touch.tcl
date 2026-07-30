##############################################################################
# pad_nets_dont_touch.tcl - hooked in as POST_FLOORPLAN_TCL by config_soc.mk
#
# WHY THIS EXISTS
#
# The SDC gained set_output_delay on the flash interface, which turned
# o_flash_ss / o_flash_mosi into constrained paths for the first time. CTS hold
# repair then found a hold violation on them and fixed it the worst possible
# way - by inserting a delay cell BETWEEN THE PAD AND THE CHIP PIN:
#
#     hold174 (sg13g2_dlygate4sd3_1)  X -> net o_flash_ss  (a top level BTERM)
#     hold176 (sg13g2_dlygate4sd3_1)  X -> net o_flash_mosi
#
# which shows up in the CTS report as
#
#     hold174/X   limit 2.51   slew 16.11   (VIOLATED)
#     hold174/X   limit 0.30   cap   4.00   (VIOLATED)
#
# The 4.00 pF is exactly the set_load from constraint_soc.sdc: a core std cell
# is now in series with the pad output, trying to drive the external load on
# its own. That defeats the whole point of picking sg13g2_IOPadOut16mA, and it
# is not something a real flow would ever produce.
#
# WHAT THIS DOES
#
# Marks every signal net that touches a BTERM as do-not-touch, i.e. the short
# nets between a pad cell and the chip pin. The resizer then has to fix hold
# further back in the core, where a delay cell belongs.
#
# It has to be done here, at floorplan, and not in the SDC: OpenSTA accepts
# set_dont_touch, but write_sdc does not emit it, so it would be dropped the
# moment the next stage regenerates the constraints. The ODB flag survives
# write_db/read_db (verified), so setting it once here carries through place,
# CTS and routing.
#
# Power and ground are skipped on purpose - pdngen adds shapes to those nets
# after this runs, and there is no reason to put a flag in its way.
##############################################################################

set blk [ord::get_db_block]
set marked 0
set skipped {}

foreach bterm [$blk getBTerms] {
    set net [$bterm getNet]
    if {$net eq "NULL"} { continue }

    # leave VDD/VSS/VDDIO/VSSIO to pdngen
    if {[$net getSigType] in {POWER GROUND}} {
        lappend skipped [$net getName]
        continue
    }

    if {![$net isDoNotTouch]} {
        $net setDoNotTouch 1
        incr marked
    }
}

puts "pad_nets_dont_touch: $marked signal nets at the boundary marked do-not-touch"
if {[llength $skipped]} {
    puts "pad_nets_dont_touch: skipped supply nets [lsort -unique $skipped]"
}
