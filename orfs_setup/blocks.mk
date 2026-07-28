# ============================================================
#  Block table - the single source of truth
# ============================================================
# Included by the top level Makefile. "make synth" and "make simulate_mixed"
# both read it, so what gets synthesized and what gets simulated cannot drift
# apart.
#
# One line per block, and only for what cannot be derived. Everything else is
# found automatically: the RTL file that defines the module (grep over the RTL
# tree), the port list and the parameter names (read from that file), the
# sub-hierarchy (ORFS runs "hierarchy -top <module>; opt_clean -purge" on the
# whole tree). Adding a block costs one word in BLOCKS.
#
#   BLOCKS           blocks "make synth_all" and "PS_BLOCKS=all" iterate over
#   CLK_<module>     clock port name for the SDC          default $(CLK)
#                    = i_wb_clk, the clock clk_gen_wb hands to the peripherals
#   PARAMS_<module>  parameters the RTL parent overrides  default: none
#
# All three can be overridden on the command line:
#   make synth MODULE=snn_lp CLK=clk PARAMS="N 8"

BLOCKS := servant_uart servant_spi

# ------------------------------------------------------------
#  PARAMS_<module>
# ------------------------------------------------------------
# A synthesized netlist has NO parameters: yosys bakes their values in. If the
# RTL parent instantiates the block with an override and it is not repeated
# here, "make synth" builds a DIFFERENT circuit than the one being simulated -
# servant_uart with its own defaults (115200 baud, 4 deep queue) gives 49 flops
# instead of 42.
#
# These values are not guessed. Synthesize the block, run
#
#     make simulate_mixed PS_BLOCKS=<module>
#
# and the generated wrapper stops at time 0 printing the values the parent
# really passes, ready to be pasted here. A block whose parent does not
# override anything needs no line at all.

# servant.v:372 instantiates it with the SoC values. With them: 42 flops,
# 3610 um2. With the module defaults: 49 flops - a different circuit.
PARAMS_servant_uart := pClockFrequency 24000000 pBaudRate 4000000 UART_QUEUE 1

# servant_spi has no line here on purpose: servant.v instantiates it without
# any override, so there is nothing to repeat. That is the normal case.
