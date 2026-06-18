# ============================================================================
#  Makefile minimale — simulazione standalone di snn_lp (dataset generico)
#  ----------------------------------------------------------------------------
#  PRIMA DI TUTTO attivare la toolchain oss-cad-suite (una volta per shell):
#      source ../gianluca_oss/oss-cad-suite/environment
#
#  FLUSSO TIPICO:
#      make prepare_data                  # estrae lo zip nella cartella dataset
#      make simulate_syntzulu_snn_lp      # compila + simula
#
#  Il dataset attivo è scelto dalla macro `PATH in rtl/define.v.
#  La variabile DATASET qui sotto DEVE combaciare con quel nome.
#  Il testbench legge TUTTI i suoi file dalla cartella $(DATASET)/:
#      flash.txt  input_even.txt  input_odd.txt  instruction.hex
#      snn_inference.txt  config.txt  decay_thr_1.txt  decay_thr_2.txt
# ============================================================================

# Nome del dataset/cartella dati (deve combaciare con `PATH in rtl/define.v)
DATASET  ?= optical_flow
# Zip da cui rigenerare i dati (sovrascrivibile: make prepare_data DATA_ZIP=...)
DATA_ZIP ?= /media/sf_cartella_condivisa_OPENHW/$(DATASET).zip

# Rigenera i dati: elimina la vecchia cartella ed estrae lo zip.
# NB: rimuove anche lo zip sorgente dopo l'estrazione.
prepare_data:
	rm -rf $(DATASET)
	unzip $(DATA_ZIP) -d ./
	rm    $(DATA_ZIP)

# Compila ed esegue la simulazione del testbench snn_lp standalone.
simulate_syntzulu_snn_lp:
	mkdir -p work
	iverilog -o rtl_sim_snn_lp \
		sim/tb/syntzulu_tb_snn_lp.sv \
		rtl/syntzulu/*.sv rtl/syntzulu/*.v
	vvp rtl_sim_snn_lp
	rm -f rtl_sim_snn_lp
	gtkwave --save=work/debug_snn_lp.gtkw syntzulu_tb_snn_lp.vcd &

clean:
	rm -f *.vcd rtl_sim_snn_lp work/*.vcd
