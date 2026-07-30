##############################################################################
# post_cts_repair.tcl - hooked in as POST_CTS_TCL by config_soc.mk
#
# WHY THIS EXISTS
#
# In variant 1 the slew violation count per stage was:
#
#     3_4_place_resized      0        <- resizer says the design is clean
#     3_5_place_dp           0
#     4_1_cts                0
#     5_1_grt              816        <- routing disagrees
#     6_finish             939
#
# Nothing degrades between CTS and global route. What changes is the source of
# the parasitics: up to CTS they are estimated from the placement, from global
# route on they are real. estimate_parasitics -placement builds a Steiner tree
# in free space and multiplies its length by the unit RC of setRC.tcl - but in
# a floorplan that is 86 % macro by area the nets do not run in free space,
# they run around the blocks. The real wire is far longer than the estimate,
# so repair_design finds nothing to do while the placement can still be
# changed, and by the time the truth arrives the cells are frozen: at global
# route it found 644 slew violations and managed to insert exactly 1 buffer.
#
# The second half of the story is RSZ-0058 in 3_4_place_resized.log:
#
#     [INFO RSZ-0058] Using max wire length 23868um
#
# 23.8 mm of allowed unbuffered wire on a 3.23 mm die. That is the default
# OpenROAD computes when -max_wire_length is not given, and ORFS never gives
# it (there is no flow variable for it). So the "this net is too long, break
# it" rule can never fire, and the ONLY thing that can trigger buffering at
# placement time is the slew/cap check - the one running on the estimate that
# is wrong. Hence 0 violations found, hence no buffers, hence 939 at the end.
#
# WHAT THIS DOES
#
# Forces the wire length criterion to a value that means something on this die.
# 600 um is roughly a fifth of the core edge: a net longer than that on this
# floorplan is almost certainly detouring around a macro. Every such net gets
# split into <= 600 um segments with a buffer at each cut, which restores the
# edge and turns one quadratic RC segment into two shorter ones.
#
# Tune 600 by how many buffers it inserts (RSZ-0038 in the log). Too small and
# it floods the channels, too large and nothing happens.
##############################################################################

# The parasitics currently in memory are whatever CTS left behind; re-estimate
# before asking repair_design to make decisions from them.
estimate_parasitics -placement

# -slew_margin/-cap_margin are PERCENTAGES: the Tcl wrapper of repair_design
# routes both through rsz::parse_percent_margin_arg. Overfixing by 20 % is the
# headroom against the underestimate described above. Keep these in step with
# SLEW_MARGIN / CAP_MARGIN in config_soc.mk.
repair_design -max_wire_length 600 -slew_margin 20 -cap_margin 20 -verbose

# MANDATORY, do not drop this. repair_design drops the buffers it inserts at
# the ideal coordinates it computed for them - overlapping macros, off site,
# on top of each other. Nothing legalises them afterwards, because this hook
# is the last thing scripts/cts.tcl runs before write_db.
#
# Leaving them unlegalised kills global routing with one of these per buffer:
#
#     [ERROR DRT-0073] No access point for wire595/A.
#     [ERROR DRT-0073] No access point for max_length1011/A.
#
# ("wire*" and "max_length*" are the names the resizer gives to wire length
# repair buffers, so the error names the cells this file created.)
#
# This is the same detailed_placement / check_placement pair that cts.tcl runs
# after its own repair_timing_helper, a few lines above where we are hooked in.
# The placement padding it needs is already set in this session by cts.tcl.
set result [catch {detailed_placement} msg]
if {$result != 0} {
    utl::error FLW 104 "detailed_placement failed after the post-CTS repair: $msg"
}
check_placement -verbose

# The 1014 buffers moved when they were legalised, so the parasitics computed
# before legalisation are stale. Refresh them or the report below is fiction.
estimate_parasitics -placement

# The point of this file is the numbers below, not the repair itself. If
# 3_4_place_resized still reports 0 slew violations on the next run and the
# count still explodes at 5_1_grt, then nothing has moved and the estimate is
# still hiding the problem - do not read the final slack as an improvement.
report_check_types -max_slew -max_capacitance -max_fanout -violators
