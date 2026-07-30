##############################################################################
# repair_helpers.tcl - sourced from platforms/ihp-sg13g2/setRC.tcl, which
# scripts/load.tcl runs at the top of EVERY stage.
#
# That detour exists because scripts/resize.tcl has no hook of its own - not a
# single "source $::env(SOMETHING_TCL)" in the whole file - and it is the one
# place where repair_design runs while the placement can still change.
#
# WHY
#
# repair_design is the only thing in the flow that can split a net with
# buffers, and it runs exactly three times:
#
#     3_4_place_resized   resize.tcl:24     parasitics: estimate   <- this file
#     4_1_cts             post_cts_repair   parasitics: estimate   600
#     5_1_grt             global_route:57   parasitics: REAL       1000
#
# ORFS never passes -max_wire_length, so OpenROAD computes its own default from
# the die - 23868 um on a 3230 um die. No net can ever qualify as long, the
# RSZ-0037 line never appears, and the splitting path is dead. Only driver
# upsizing is left, and that does not help a net dominated by its own wire RC:
#
#     tau ~ R_driver x (C_wire + C_load)  +  R_wire x (C_wire/2 + C_load)
#           \___ upsizing fixes this ___/     \___ upsizing cannot ____/
#
# The second term grows as L^2. Splitting a net in half turns 2 x (L/2)^2 into
# L^2/2 - the only real cure, and it was switched off in two of the three
# passes above.
#
# Measured at global route in variant 2, with the default still in force:
# 734 slew violations found, 107 instances resized, ZERO buffers inserted.
#
# WHAT
#
# Same proc as scripts/util.tcl:42 with one line added. Kept as a full copy on
# purpose - if upstream changes that proc this override goes stale silently, so
# diff the two when bumping the ORFS version.
#
# With MAX_WIRE_LENGTH unset the appended argument disappears and the proc
# behaves exactly like stock ORFS, so this file is inert by default.
#
# NOTE ON SCOPE: being sourced at load time, this redefinition is in force for
# every stage. global_route.tcl:10 sources pre_global_route.tcl afterwards,
# which redefines the same proc with a looser threshold - deliberate, because
# there the length measured is the real routed one rather than a Steiner
# estimate in free space, so the same number would catch far more nets.
##############################################################################

proc repair_design_helper {} {
  puts "Perform buffer insertion and gate resizing..."

  set additional_args "-verbose"
  append_env_var additional_args CAP_MARGIN -cap_margin 1
  append_env_var additional_args SLEW_MARGIN -slew_margin 1
  append_env_var additional_args MATCH_CELL_FOOTPRINT -match_cell_footprint 0
  append_env_var additional_args MAX_WIRE_LENGTH -max_wire_length 1

  log_cmd repair_design {*}$additional_args
}
