# ============================================================================
#  Minimal Makefile — standalone simulation of snn_lp (generic dataset)
#  ----------------------------------------------------------------------------
#  FIRST OF ALL activate the oss-cad-suite toolchain (once per shell):
#      source <path-to>/oss-cad-suite/environment
#
#  TYPICAL FLOW:
#      make prepare_data                  # extract the zip into the dataset folder
#      make simulate_syntzulu_snn_lp      # compile + simulate
#      make wave                          # open the waveform in GTKWave (optional)
#
#  The active dataset is selected by the `PATH macro in rtl/define.v.
#  The DATASET variable below MUST match that name.
#  The testbench reads ALL of its files from the $(DATASET)/ folder:
#      flash.txt  input_even.txt  input_odd.txt  instruction.hex
#      snn_inference.txt  config.txt  decay_thr_1.txt  decay_thr_2.txt
# ============================================================================

# Toolchain executables (override to point at a different install)
IVERILOG ?= iverilog
VVP      ?= vvp
GTKWAVE  ?= gtkwave

# Dataset/data folder name (must match the `PATH macro in rtl/define.v)
DATASET  ?= optical_flow
# Zip the data is regenerated from (override: make prepare_data DATA_ZIP=...)
DATA_ZIP ?= /media/sf_cartella_condivisa_OPENHW/$(DATASET).zip

# Simulation artifacts
SIM_BIN  := rtl_sim_snn_lp
VCD      := syntzulu_tb_snn_lp.vcd

# Source lists (tc_sram.sv is excluded: the sim uses tc_sram_fake.sv instead)
RTL_SRCS := sim/tb/syntzulu_tb_snn_lp.sv \
            $(wildcard rtl/syntzulu/*.sv) $(wildcard rtl/syntzulu/*.v) \
            $(filter-out rtl/primitive/tc_sram.sv,$(wildcard rtl/primitive/*.sv))

.PHONY: prepare_data simulate_syntzulu_snn_lp wave clean

# Regenerate the data: remove the old folder and extract the zip.
# The source zip is left in place.
prepare_data:
	rm -rf $(DATASET)
	unzip $(DATA_ZIP) -d ./

# Compile and run the standalone snn_lp testbench simulation.
simulate_syntzulu_snn_lp:
	mkdir -p work
	$(IVERILOG) -g2012 -o $(SIM_BIN) $(RTL_SRCS)
	$(VVP) $(SIM_BIN)
	rm -f $(SIM_BIN)

# Open the generated waveform in GTKWave (separate from the sim so the
# simulate target stays headless/CI friendly).
wave:
	$(GTKWAVE) --save=work/debug_snn_lp.gtkw $(VCD) &

clean:
	rm -f *.vcd $(SIM_BIN) work/*.vcd
