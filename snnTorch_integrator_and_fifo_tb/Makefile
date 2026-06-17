# Makefile for integrator_and_fifo_snnTorch testbench
#
# Targets:
#   make sim   -> compile + run the testbench
#   make wave  -> open the produced VCD with gtkwave
#   make clean -> remove generated files

ROOT     := ../rtl/syntzulu
TB       := tb_integrator_and_fifo_snnTorch.sv
SIM_BIN  := sim.out
VCD      := wave.vcd

RTL_SRCS := \
	$(ROOT)/integrator_and_fifo_snnTorch.sv \
	$(ROOT)/integrator_snnTorch.sv \
	$(ROOT)/buffer_current_mem.sv \
	$(ROOT)/bram_fifo.sv \
	$(ROOT)/dec_thr_mem.sv \
	$(ROOT)/BRAM_singlePort_readFirst.sv

IVERILOG ?= iverilog
VVP      ?= vvp
GTKWAVE  ?= gtkwave

.PHONY: sim wave clean

sim: $(SIM_BIN)
	$(VVP) $(SIM_BIN)

$(SIM_BIN): $(TB) $(RTL_SRCS)
	$(IVERILOG) -g2012 -o $@ $(TB) $(RTL_SRCS)

wave: $(VCD)
	$(GTKWAVE) $(VCD) onde.gtkw &

clean:
	rm -f $(SIM_BIN) $(VCD)
