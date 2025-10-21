`timescale 1ns / 1ps
`default_nettype none
module servant_tb;

   parameter memfile = "firmware/exe.hex";
   parameter memsize = 3456;
   parameter with_csr = 1;

   reg wb_clk = 1'b0;
   reg wb_rst = 1'b1;

   wire q;
   reg [2:0] buttons = 15;

   always  #31 wb_clk <= !wb_clk;
   initial #62 wb_rst <= 1'b0;

   //uart_decoder #(2000000) uart_decoder (q);

   servant_sim
     #(.memfile  (memfile),
       .memsize  (memsize),
       .with_csr (with_csr))
   servant_sim_i
     (.wb_clk (wb_clk),
      .wb_rst (wb_rst),
      .pc_adr (),
      .pc_vld (),
      .q      (q),
      .buttons(buttons));

parameter OUTPUT_FILE_TARGET   = {"sim/results/",`PATH,"/snn_inference.txt"};
parameter TARGET_FILE          = {"sim/target/",`PATH,"/snn_inference.txt"};
parameter TARGET_FILE_BINNING  = {"sim/target/",`PATH,"/encoded_input.txt"};
parameter OUTPUT_FILE_BINNING  = {"sim/results/",`PATH,"/encoded_input.txt"};

parameter MAX_ERRORS = 1000;

integer i,j,k;
integer f_t_bin, f_out_bin;
integer f_out_target, f_out;

initial begin
`ifndef PSIM
  $dumpfile("tb_serv.vcd");
`else
  $dumpfile("ps_tb_serv.vcd");
`endif
  $dumpvars(10,servant_tb);

  f_out_target = $fopen(TARGET_FILE,"r");
  f_out        = $fopen(OUTPUT_FILE_TARGET,"w");

  f_t_bin      = $fopen(TARGET_FILE_BINNING,"r");
  f_out_bin    = $fopen(OUTPUT_FILE_BINNING,"w");

  #20000
  buttons = 0;
  #70000000;

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

  // prendi i segnali come mi hai indicato
  assign valid_snn = servant_sim_i.service_i.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.valid_fifo;
  assign p1        = servant_sim_i.service_i.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.output_new;
  assign p2        = servant_sim_i.service_i.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.output_new;

  // target da file (due numeri per ciascun valid: p1 atteso e p2 atteso)
  integer signed target_p1;
  integer signed target_p2;

  always @(posedge wb_clk) begin
    if (valid_snn) begin
      sample_idx <= sample_idx + 1;

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

  // =========================
  //  ENCODING CHECK
  // =========================
  reg  [3:0] target_bins;
  integer    jj = 0;
  integer    error_bin = 0;
  wire [3:0] bin;
  assign bin = servant_sim_i.service_i.mosquito.encoding_slot_i.encoding_slot_emg_i.spike_bin;
  wire       valid_bin;
  assign valid_bin = servant_sim_i.service_i.mosquito.encoding_slot_i.encoding_slot_emg_i.valid_bin;

  always @(posedge wb_clk) begin
    if(valid_bin) begin
      jj = jj + 1;
      $fwrite(f_out_bin,"%b ", bin);
      if(((jj%8) == 0) && (jj != 0))
        $fwrite(f_out_bin,"\n");
      dummy = $fscanf(f_t_bin, "%b ", target_bins);
		if(bin != target_bins) begin
			error_bin = error_bin + 1;
			$display("#Error bin @(%0d)\t[jj=%0d]", jj/32+1, jj);
			$display("target_bins = %0d, bin = %0d", target_bins, bin);
      end
    end
  end

`endif

endmodule
