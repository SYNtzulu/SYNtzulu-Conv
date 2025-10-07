filename = Syntzulu
pcf_file = rtl/icebreaker.pcf

env:
	cd ../ && source oss-cad-suite/environment

build:
	cd firmware && make -B
	yosys -p "synth_ice40 -dsp -top service -json output/$(filename).json -blif output/$(filename).blif -noflatten" rtl/define.v rtl/servant/* rtl/serv/* rtl/syntzulu/* -l output/yosys.log
	nextpnr-ice40 --up5k --json output/$(filename).json --pcf $(pcf_file) --asc output/$(filename).asc -l output/nextpnr.log -v
	icepack output/$(filename).asc output/$(filename).bin -s
	
build_stat:
	cd firmware && make -B
	yosys -p "read_verilog -sv rtl/define.v rtl/servant/* rtl/serv/* rtl/syntzulu/*; \
	          hierarchy -top service; \
	          synth_ice40 -top service -dsp -abc9 -noflatten; \
	          tee -o output/module_stats.txt stat" \
	     -l output/yosys_stat.log

build_no_flatten:
	cd firmware && make -B
	yosys -p "synth_ice40 -dsp -abc9 -top service -json output/$(filename).json -blif output/$(filename).blif -noflatten" rtl/define.v rtl/servant/* rtl/serv/* rtl/syntzulu/* -l output/yosys_noflatt.log

build_one:
	cd firmware && make -B
	yosys -p "synth_ice40 -abc9 -top integrator_new -json output/$(filename).json -blif output/$(filename).blif -flatten" rtl/syntzulu/integrator_new.sv -l output/yosys.log
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
	iverilog -g2012 -o rtl_sim  sim/test_tb/tb_PE.v rtl/syntzulu/priority_encoder.sv 
	vvp rtl_sim
	rm rtl_sim 
	mv tb_encoder.vcd work/
	gtkwave --save=work/serv_waves_encoder.gtkw work/tb_encoder.vcd &

simulate:
	cd firmware && make -B
	iverilog -o rtl_sim  rtl/define.v sim/tb/servant_tb_conv.v sim/tb/servant_sim.v sim/tb/uart_decoder.v sim/tb/vlog_tb_utils.v sim/tb/flash_spi_sim.sv rtl/servant/* rtl/serv/* rtl/syntzulu/* rtl/primitive/*
	vvp rtl_sim
	rm rtl_sim 
	mv tb_serv.vcd work/
	gtkwave --save=work/serv_waves.gtkw work/tb_serv.vcd &

psimulate: 
	yosys -p 'read_blif -wideports output/$(filename).blif; write_verilog output/top_syn.v'
	iverilog -g2012 -o gate_sim rtl/psim.v rtl/define.v sim/tb/servant_tb.v sim/tb/servant_sim.v sim/tb/uart_decoder.v sim/tb/vlog_tb_utils.v sim/tb/flash_spi_sim.sv output/top_syn.v sim/tb/cells_sim.v sim/tb/SB_PLL40_PAD.v sim/tb/SB_PLL40_2F_PAD.v
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
	mkdir -p rtl/config/$(app) sim/mem/$(app) sim/target/$(app) sim/results/$(app);\
	cp $(app)/config.txt rtl/config/$(app)/; \
	cp $(app)/delta.txt sim/mem/$(app)/; \
	cp $(app)/flash.txt sim/mem/$(app)/; \
	cp $(app)/encoded_input.txt sim/target/$(app)/; \
	cp $(app)/snn_inference.txt sim/target/$(app)/; \
	cp $(app)/spike_1.txt sim/target/$(app)/
	mkdir firmware/src/applications/$(app)/
	cp $(app)/*.h firmware/src/applications/$(app)/
	cd firmware && make -B compile app=$(app)
	mkdir flash/src/$(app)/
	cp $(app)/weights_1.txt $(app)/weights_2.txt $(app)/weights_3.txt $(app)/weights_4.txt $(app)/address.txt $(app)/samples.txt flash/src/$(app)/

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
