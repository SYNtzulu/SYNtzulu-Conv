`timescale 1ns / 1ps
`default_nettype none
module servant_tb;

   parameter memfile = "firmware/exe.hex";
   parameter memsize = 3456;
   parameter with_csr = 1;
   parameter HFOSC = "0b01"; // "0b00" = 48 MHz, "0b01" = 24 MHz, "0b10" = 12 MHz, "0b11" = 6 MHz


   reg i_clk = 1'b0;
   reg i_rst = 1'b1;

   wire q;
   reg [2:0] buttons = 15;

   always  #5 i_clk <= !i_clk;
   initial #10 i_rst <= 1'b0;

   uart_decoder #(4000000) uart_decoder (q);

    wire wb_clk;
    assign wb_clk = servant_sim_i.soc_i.servant.wb_clk; 

   servant_sim
     #(.memfile  (memfile),
       .memsize  (memsize),
       .with_csr (with_csr))
   servant_sim_i
     (.wb_clk (i_clk),
      .wb_rst (i_rst),
      .pc_adr (),
      .pc_vld (),
      .q      (q),
      .buttons(buttons));

parameter OUTPUT_FILE_TARGET   = {"sim/results/",`PATH,"/snn_inference.txt"};
parameter LABEL_FILE_OUTPUT   = {"sim/results/",`PATH,"/label.txt"};
parameter TARGET_FILE          = {"sim/target/",`PATH,"/snn_inference.txt"};
parameter TARGET_FILE_BINNING= {"sim/target/",`PATH,"/spike_vec.txt"};
parameter OUTPUT_FILE_BINNING = {"sim/results/",`PATH,"/spike_vec.txt"};

parameter MAX_ERRORS = 1000;

integer i,j,k;
integer f_t_bin, f_out_bin;
integer f_out_target, f_out, f_label;

initial begin
`ifndef PSIM
  $dumpfile("tb_serv.vcd");
`else
  $dumpfile("ps_tb_serv.vcd");
`endif
  $dumpvars(0,servant_tb);

  f_out_target = $fopen(TARGET_FILE,"r");
  f_out        = $fopen(OUTPUT_FILE_TARGET,"w");
  f_label       = $fopen(LABEL_FILE_OUTPUT,"w");

  #20000
  buttons = 0;
  #5000000;
  //#2000000000;

  $fclose(f_out);
  $fclose(f_out_target);
  $fclose(f_out_bin);
  $fclose(f_t_bin);

  //$display("#[VERIFICATE #%0d  CORRENTI\nERRORI TOTALI: #%0d]", sample_idx, errors_snn_inference);
  $finish;
end

`ifndef PSIM

  // =========================
  //  SNN CURRENTS CHECK
  // =========================
  integer errors_snn_inference = 0;
  integer dummy;
  integer sample_idx = 0;

  // correnti “p1/p2” esposte dall’hardware (una coppia per valid)
  wire signed [15:0] p1;
  wire signed [15:0] p2;
  wire               valid_snn;
  wire valid_label;
  wire [31:0] label;
  wire pooling_enable;

  assign pooling_enable = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.pooling_enable;

  assign valid_snn = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.valid_fifo;
  assign p1        = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in;
  assign p2        = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in;

  assign valid_label = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.output_buffer_wr_en;
  assign label = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.output_buffer_din;

  // target da file (due numeri per ciascun valid: p1 atteso e p2 atteso)
  integer signed target_p1;
  integer signed target_p2;

  always @(posedge wb_clk) begin
    if (!pooling_enable & valid_snn) begin
      sample_idx <= sample_idx + 1;
      if(valid_label)
        $fwrite(f_label,"[%0d\n", label);
      // log corrente HW
      $fwrite(f_out,"[%0d,%0d],\n", $signed(p1), $signed(p2));
      $display("#[VALID #%0d  \tHW: p1=%0d  \tp2=%0d]", sample_idx, $signed(p1), $signed(p2));

      // leggi due target consecutivi (p1 poi p2) dal file
      if (!$feof(f_out_target)) begin
        dummy = $fscanf(f_out_target, "%d\n", target_p1);
      end else begin
        $display("WARNING: EOF su target durante lettura target_p1 @%0d", sample_idx);
        target_p1 = 0;
      end

      if (!$feof(f_out_target)) begin
        dummy = $fscanf(f_out_target, "%d\n", target_p2);
      end else begin
        $display("WARNING: EOF su target durante lettura target_p2 @%0d", sample_idx);
        target_p2 = 0;
      end

      // confronti
      if (target_p1 !== $signed(p1)) begin
        errors_snn_inference = errors_snn_inference + 1;
        $display("#ERR p1 @%0d  exp=%0d  got=%0d", sample_idx, target_p1, $signed(p1));
      end
      if (target_p2 !== $signed(p2)) begin
        errors_snn_inference = errors_snn_inference + 1;
        $display("#ERR p2 @%0d  exp=%0d  got=%0d", sample_idx, target_p2, $signed(p2));
      end

      if (errors_snn_inference > MAX_ERRORS) begin
        $display("Troppi errori (%0d). Stop.", errors_snn_inference);
        $finish;
      end
    end
  end


	/*
		                       _ _             
	   ___ _ __   ___ ___   __| (_)_ __   __ _ 
	  / _ \ '_ \ / __/ _ \ / _` | | '_ \ / _` |
	 |  __/ | | | (_| (_) | (_| | | | | | (_| |
	  \___|_| |_|\___\___/ \__,_|_|_| |_|\__, |
		                                 |___/ 
	*/
/*
	reg [3:0] target_bins;
	integer jj = 0;
	integer error_bin = 0;
	wire [3:0] bin;
	assign bin = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.encoding_slot_i.encoding_slot_emg_i.spike_bin;
	wire valid_bin;
	assign valid_bin = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.encoding_slot_i.encoding_slot_emg_i.valid_bin;

	always @(valid_bin) begin
		if(valid_bin) begin
			jj = jj + 1;
			$fwrite(f_out_bin,"%b ", bin);
			if(((jj%8) == 0) && (jj != 0))
				$fwrite(f_out_bin,"\n");
			dummy = $fscanf(f_t_bin, "%b ", target_bins);
			for(k=0;k<4;k=k+1) begin
				if(bin[k] != target_bins[k]) begin
					error_bin = error_bin + 1;
				    $display("#Error detected @(%d,%d)[jj=%d,k=%d]\n",jj/32+1,4*(jj%32)-k,jj,k);
				    $display("target_bins = %d, bin = %d\n",target_bins,bin);
				end
			end 
		end
	end*/


`endif

endmodule
