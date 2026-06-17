# ============================================================================
#  Makefile minimale — simulazione standalone di snn_lp (MNIST)
#  ----------------------------------------------------------------------------
#  PRIMA DI TUTTO attivare la toolchain oss-cad-suite (una volta per shell):
#      source ../gianluca_oss/oss-cad-suite/environment
#
#  FLUSSO TIPICO:
#      make prepare_mnist                 # rigenera i dati dallo zip
#      make simulate_syntzulu_snn_lp      # compila + simula
#
#  Il testbench legge TUTTI i suoi file direttamente dalla cartella mnist/:
#      mnist/flash.txt  mnist/input_even.txt  mnist/input_odd.txt
#      mnist/instruction.hex  mnist/snn_inference.txt  mnist/config.txt
#      mnist/decay_thr_1.txt  mnist/decay_thr_2.txt
# ============================================================================

# Percorso dello zip dei dati (sovrascrivibile: make prepare_mnist MNIST_ZIP=...)
MNIST_ZIP ?= /media/sf_cartella_condivisa_OPENHW/mnist.zip

# Rigenera i dati: elimina la vecchia cartella mnist/ ed estrae lo zip.
# Dopo questo, il TB ha tutto ciò che gli serve dentro mnist/.
prepare_mnist:
	rm -rf mnist
	unzip $(MNIST_ZIP) -d ./

# Compila ed esegue la simulazione del testbench snn_lp standalone (MNIST).
simulate_syntzulu_snn_lp:
	mkdir -p work
	iverilog -o rtl_sim_snn_lp \
		sim/tb/syntzulu_tb_mnist_snn_lp.sv \
		rtl/syntzulu/*.sv rtl/syntzulu/*.v \
		rtl/primitive/*.sv rtl/primitive/*.v
	vvp rtl_sim_snn_lp
	rm -f rtl_sim_snn_lp
	gtkwave --save=work/debug_snn_lp.gtkw syntzulu_tb_mnist_snn_lp.vcd &

clean:
	rm -f *.vcd rtl_sim_snn_lp work/*.vcd
