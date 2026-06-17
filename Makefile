filename = top
pcf_file = rtl/icebreaker.pcf

env:
	cd ../ && source oss-cad-suite/environment
	
netlist:
	yosys -p 'read_blif -wideports output/$(filename).blif; write_verilog output/top_syn.v'
	
build:
	cd firmware && make -B
	yosys -p "synth_ice40 -abc9 -top soc -json output/$(filename).json -blif output/$(filename).blif -flatten" rtl/define.v rtl/servant/* rtl/serv/* rtl/syntzulu/* -l output/yosys.log
	nextpnr-ice40 --up5k --seed 108 --json output/$(filename).json --pcf $(pcf_file) --asc output/$(filename).asc -l output/nextpnr.log -v 
	icepack output/$(filename).asc output/$(filename).bin -s
	
build_stat:
	cd firmware && make -B
	yosys -p "read_verilog -sv rtl/define.v rtl/servant/* rtl/serv/* rtl/syntzulu/*; \
	          hierarchy -top soc; \
	          synth_ice40 -top soc -dsp -abc9 -noflatten; \
	          tee -o output/module_stats.txt stat" \
	     -l output/yosys_stat.log

# Lista di seed da testare (modifica liberamente)
SEEDS = 1 2 3 4 5 6 7 8 9 10 37 42 99

build_best:
	cd firmware && make -B
	@mkdir -p logs output/best
	@rm -f output/best_freq.txt
	yosys -p "synth_ice40 -abc9 -top soc -json output/$(filename).json -blif output/$(filename).blif -flatten" rtl/define.v rtl/servant/* rtl/serv/* rtl/syntzulu/* -l output/yosys.log
	@echo "Seed | Fmax (MHz)" > output/best_freq.txt
	@for SEED in $$(seq 101 200); do \
		echo ">>> Trying seed $$SEED..."; \
		nextpnr-ice40 --up5k --package sg48 \
			--json output/$(filename).json \
			--pcf $(pcf_file) \
			--asc output/best/$(filename)_seed$$SEED.asc \
			--threads $$(nproc) \
			--freq 24 \
			--seed $$SEED --timing-allow-fail \
			> logs/nextpnr_seed$$SEED.log 2>&1; \
		FREQ=$$(grep -E "Max frequency for clock 'servant\.wb_clk'" logs/nextpnr_seed$$SEED.log | \
			sed -E "s/.*: ([0-9]+\.[0-9]+) MHz.*/\1/" | tail -n 1); \
		[ -z "$$FREQ" ] && FREQ=$$(grep -Eo "([0-9]+\.[0-9]+) MHz" logs/nextpnr_seed$$SEED.log | tail -n 1 | cut -d' ' -f1); \
		[ -z "$$FREQ" ] && FREQ="0.00"; \
		echo "Seed $$SEED => $$FREQ MHz"; \
		echo "$$SEED | $$FREQ" >> output/best_freq.txt; \
	done; \
	tail -n +2 output/best_freq.txt | sort -nr -k2,2 -t'|' > output/best/best_seed.txt; \
	BEST_SEED=$$(head -n1 output/best/best_seed.txt | cut -d '|' -f1 | tr -d ' '); \
	cp output/best/$(filename)_seed$$BEST_SEED.asc output/$(filename).asc; \
	echo "==> Best seed: $$BEST_SEED"; \
	icepack output/$(filename).asc output/$(filename).bin -s

build_no_flatten:
	cd firmware && make -B
	yosys -p "synth_ice40 -dsp -abc9 -top service -json output/$(filename).json -blif output/$(filename).blif -noflatten" rtl/define.v rtl/servant/* rtl/serv/* rtl/syntzulu/* -l output/yosys_noflatt.log

build_one:
	cd firmware && make -B
	yosys -p "synth_ice40 -abc9 -top stack_bram -json output/$(filename).json -blif output/$(filename).blif -flatten" rtl/syntzulu/stack_bram.sv rtl/syntzulu/BRAM_singlePort_readFirst.sv -l output/yosys.log
	#nextpnr-ice40 --up5k --json output/$(filename).json --pcf $(pcf_file) --asc output/$(filename).asc -l output/nextpnr.log -v
	#icepack output/$(filename).asc output/$(filename).bin -s

build_cr:
	cd firmware && make -B
	yosys -p "synth_ice40 -dsp -abc9 -top service -json output/$(filename).json -blif output/$(filename).blif -flatten" rtl/define.v rtl/servant/* rtl/serv/* rtl/syntzulu/* -l output/yosys.log
	nextpnr-ice40 --json output/$(filename).json --pcf $(pcf_file) --up5k --asc output/$(filename).asc --report timing_report.json
	@ if [ $$? -ne 0 ]; then echo "WARNING: Timing violation, continuing anyway..."; fi
	icepack output/$(filename).asc output/$(filename).bin -s

prog:
	sudo iceprog output/$(filename).bin
	
simulate_sy:
	#cd firmware && make -B
	iverilog -g2012 -o rtl_sim sim/test_tb/tb_decoder.sv rtl/syntzulu/decoding_slot_mnist.sv rtl/primitive/SB_RAM40_4K.sv
	vvp rtl_sim
	rm rtl_sim 
	mv tb_decoder.vcd work/
	gtkwave --save=work/serv_waves_decoder.gtkw work/tb_decoder.vcd &

simulate:
	cd firmware && make -B
	iverilog -o rtl_sim  rtl/define.v sim/tb/servant_tb_mnist.v sim/tb/servant_sim.v sim/tb/uart_decoder.v sim/tb/vlog_tb_utils.v sim/tb/flash_spi_sim.sv rtl/servant/* rtl/serv/* rtl/syntzulu/* rtl/primitive/* sim/tb/SB_HFOSC.v sim/tb/SB_LFOSC.v
	vvp rtl_sim
	rm rtl_sim 
	mv tb_serv.vcd work/
	gtkwave --save=work/debug.gtkw work/tb_serv.vcd &

	
simulate_syntzulu:
	mkdir -p sim/results/mnist work
	iverilog -o rtl_sim_2 \
		sim/tb/syntzulu_tb_mnist.sv \
		rtl/syntzulu/*.sv rtl/syntzulu/*.v \
		rtl/primitive/*.sv rtl/primitive/*.v
	vvp rtl_sim_2
	rm -f rtl_sim_2
	cp sim/results/mnist/syntzulu_tb_mnist.vcd work/ 2>/dev/null || true
	gtkwave sim/results/mnist/syntzulu_tb_mnist.vcd &

simulate_syntzulu_snn_lp:
	mkdir -p sim/results/mnist work
	iverilog -o rtl_sim_snn_lp \
		sim/tb/syntzulu_tb_mnist_snn_lp.sv \
		rtl/syntzulu/*.sv rtl/syntzulu/*.v \
		rtl/primitive/*.sv rtl/primitive/*.v
	vvp rtl_sim_snn_lp
	rm -f rtl_sim_snn_lp
	gtkwave --save=work/debug_snn_lp.gtkw syntzulu_tb_mnist_snn_lp.vcd &

psimulate: 
	yosys -p 'read_blif -wideports output/$(filename).blif; write_verilog output/top_syn.v'
	iverilog -g2012 -o gate_sim rtl/psim.v rtl/define.v sim/tb/servant_tb_mnist.v sim/tb/servant_sim.v sim/tb/uart_decoder.v sim/tb/vlog_tb_utils.v sim/tb/flash_spi_sim.sv output/top_syn.v sim/tb/cells_sim.v sim/tb/SB_PLL40_PAD.v sim/tb/SB_PLL40_2F_PAD.v sim/tb/SB_HFOSC.v sim/tb/SB_LFOSC.v
	vvp gate_sim
	rm gate_sim 
	mv ps_tb_serv.vcd work/
	gtkwave --save=work/ps_serv_waves.gtkw work/ps_tb_serv.vcd &
	
psimulate_new:
	yosys -p 'read_json output/$(filename).json; hierarchy -top soc; write_verilog -noattr -norename output/top_syn.v'
	iverilog -g2012 -o gate_sim \
		rtl/psim.v rtl/define.v \
		sim/tb/servant_tb_mnist.v sim/tb/servant_sim.v \
		sim/tb/uart_decoder.v sim/tb/vlog_tb_utils.v \
		sim/tb/flash_spi_sim.sv output/top_syn.v \
		sim/tb/cells_sim.v sim/tb/SB_HFOSC.v sim/tb/SB_LFOSC.v
	vvp gate_sim
	rm gate_sim
	mv ps_tb_serv.vcd work/
	gtkwave --save=work/ps_serv_waves.gtkw work/ps_tb_serv.vcd &


listen:
	sudo rm -f output/serial.txt || true
	sudo minicom -b 4000000 -H -C output/serial.txt -D /dev/ttyUSB1

create_application:
	@if [ -z "$(app)" ]; then \
		echo "Usage: make create_application app=<application_name>"; \
		exit 1; \
	fi
	unzip /media/sf_cartella_condivisa_OPENHW/mnist.zip -d ./
	mkdir -p rtl/config/$(app) sim/mem/$(app) sim/target/$(app) sim/results/$(app);\
	cp $(app)/config.txt rtl/config/$(app)/; \
	cp $(app)/delta.txt sim/mem/$(app)/; \
	cp $(app)/flash.txt sim/mem/$(app)/; \
	cp $(app)/encoded_input.txt sim/target/$(app)/; \
	cp $(app)/snn_inference.txt sim/target/$(app)/; \
	#cp $(app)/spike_1.txt sim/target/$(app)/
	mkdir firmware/src/applications/$(app)/
	cp $(app)/*.h firmware/src/applications/$(app)/
	cd firmware && make -B compile app=$(app)
	mkdir flash/src/$(app)/
	cp $(app)/weights_1.txt $(app)/weights_2.txt $(app)/weights_3.txt $(app)/weights_4.txt $(app)/address.txt $(app)/samples.txt $(app)/instruction.hex flash/src/$(app)/
	@python3 python/describe_simulation.py $(app) flash/src/$(app)/instruction.hex rtl/config/$(app)/config.txt firmware/src/applications/$(app)/constants.h simulation_$(app).txt

describe:
	@if [ -z "$(app)" ]; then \
		echo "Usage: make describe app=<application_name>"; \
		exit 1; \
	fi
	@python3 python/describe_simulation.py $(app) flash/src/$(app)/instruction.hex rtl/config/$(app)/config.txt firmware/src/applications/$(app)/constants.h simulation_$(app).txt

clean_application:
	@if [ -z "$(app)" ]; then \
		echo "Usage: make clean_application app=<application_name>"; \
		exit 1; \
	fi
	rm -r rtl/config/$(app)/; \
	rm -r sim/mem/$(app)/; \
	rm -r sim/target/$(app)/; \
	rm -r sim/results/$(app)/; \
	rm -r firmware/src/applications/$(app)/; \
	rm -r flash/src/$(app)/; \

clean_all_applications:
	rm -r /media/sf_cartella_condivisa_OPENHW/mnist.zip
	rm -r mnist
	rm -f *.vcd 
	rm -f rtl_sim
	rm -f gate_sim
	rm -r rtl/config/*; \
	rm -r sim/mem/*; \
	rm -r sim/target/*; \
	rm -r sim/results/*; \
	rm -r firmware/src/applications/*; \
	rm -r flash/src/*; \
	rm -r flash/from_flash/*; \
	rm -r flash/to_flash/*; \
	rm -r output/*

clean:
	rm -f *.vcd 
	rm -f rtl_sim
	rm -f gate_sim
	rm -f work/*.vcd
