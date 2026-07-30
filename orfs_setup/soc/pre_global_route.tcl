##############################################################################
# pre_global_route.tcl - hooked in as PRE_GLOBAL_ROUTE by config_soc.mk
#
# Sourced at scripts/global_route.tcl:10, before the stage does anything.
# load.tcl has already run, so util.tcl's procs exist and can be overridden.
#
# WHY
#
# At global route ORFS calls repair_design_helper (global_route.tcl:57) right
# after estimate_parasitics -global_routing - the only point in the flow where
# the resizer sees parasitics derived from the real routed topology. In
# variant 2 that call reported:
#
#     [INFO RSZ-0034] Found 734 slew violations.
#     [INFO RSZ-0036] Found 492 capacitance violations.
#     [INFO RSZ-0039] Resized 107 instances.
#
# and nothing else. No RSZ-0038 (buffers inserted), no RSZ-0037 (long wires
# found) - both lines simply absent. Variant 1 was the same: 644 slew
# violations, 1 buffer.
#
# repair_design has two ways to fix a slew violation: upsize the driver, or
# split the net with buffers. Splitting is gated on the max wire length, and
# ORFS never passes -max_wire_length, so OpenROAD computes its own default -
# 23868 um on a 3230 um die. No net can ever qualify, RSZ-0037 never fires,
# and the splitting path is dead. Only upsizing is left.
#
# Upsizing does not help these nets. Their delay is dominated by the wire's
# own RC, which grows as L^2 and which the driver cannot touch:
#
#     tau ~ R_driver x (C_wire + C_load)  +  R_wire x (C_wire/2 + C_load)
#           \___ upsizing fixes this ___/     \___ upsizing cannot ____/
#
# Splitting a net in half turns 2 x (L/2)^2 = L^2/2 - half the delay, plus a
# small constant buffer delay. That is the only cure, and it is switched off.
#
# WHAT
#
# Same proc as scripts/util.tcl:42, plus -max_wire_length. Kept as a copy on
# purpose: if ORFS changes the original, this override silently goes stale, so
# diff it against util.tcl when bumping the ORFS version.
#
# ON THE VALUE - 1000, NOT THE 600 USED AT CTS.
# The two thresholds do not measure the same thing. post_cts_repair.tcl runs
# on estimate_parasitics -placement, where the length is a Steiner estimate in
# free space. Here the length comes from the real routing, which detours around
# the macros and is therefore longer. The same number would catch far more
# nets: 600 found 621 long wires at CTS, and would likely find two to three
# times as many here.
#
# That matters because every buffer inserted at this point has to be legalised
# into an already dense placement and forces a rip-up and reroute of its net
# (global_route.tcl:64-67). The bill lands on detailed route, which is 50 of
# the flow's 70 minutes and the stage most likely to stop converging.
#
# So: start loose, catch only the genuinely pathological nets, and tighten
# later while watching the RSZ-0038 count and the detailed route runtime.
##############################################################################

proc repair_design_helper {} {
  puts "Perform buffer insertion and gate resizing... (max_wire_length override)"

  set additional_args "-verbose"
  append_env_var additional_args CAP_MARGIN -cap_margin 1
  append_env_var additional_args SLEW_MARGIN -slew_margin 1
  append_env_var additional_args MATCH_CELL_FOOTPRINT -match_cell_footprint 0
  append additional_args " -max_wire_length 1000"

  log_cmd repair_design {*}$additional_args
}
