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

parameter MAX_ERRORS = 10;

integer i,j,k;
integer f_t_bin, f_out_bin;
integer f_out_target, f_out, f_label;

initial begin
`ifndef PSIM
  $dumpfile("tb_serv.vcd");
`else
  $dumpfile("ps_tb_serv.vcd");
`endif
  $dumpvars(0, servant_tb);

  f_out_target = $fopen(TARGET_FILE,"r");
  f_out        = $fopen(OUTPUT_FILE_TARGET,"w");
  f_label      = $fopen(LABEL_FILE_OUTPUT,"w");

  #20000
  buttons = 0;
  //#300  000 000;
  //#70000000;
  #1400000000;

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

  // === buffer_current di L1/L2 ===
  // - buffer_current   : uscita del buffer_current_mem (combinazionale)
  // - buffer_current_d : versione registrata (feed all'integrator), questa è
  //                      la corrente effettivamente integrata
  // - valid_buffer_current(_d) : enable corrispondente
  wire signed [15:0] buf_curr_l1;
  wire signed [15:0] buf_curr_l2;
  wire signed [15:0] buf_curr_d_l1;
  wire signed [15:0] buf_curr_d_l2;
  wire               valid_buf_curr_l1;
  wire               valid_buf_curr_l2;
  wire               valid_buf_curr_d_l1;
  wire               valid_buf_curr_d_l2;

  assign valid_snn = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.valid_fifo;
  assign p1        = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.output_new;
  assign p2        = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.output_new;

  assign buf_curr_l1   = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.buffer_current;
  assign buf_curr_l2   = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.buffer_current;
  assign buf_curr_d_l1 = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.buffer_current_d;
  assign buf_curr_d_l2 = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.buffer_current_d;
  assign valid_buf_curr_l1   = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.valid_buffer_current;
  assign valid_buf_curr_l2   = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.valid_buffer_current;
  assign valid_buf_curr_d_l1 = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.valid_buffer_current_d;
  assign valid_buf_curr_d_l2 = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.valid_buffer_current_d;

  assign valid_label = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.output_buffer_wr_en;
  assign label = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.output_buffer_din;

  // === Address pointer di buffer_current_mem (L1/L2) ====================
  wire [7:0] buf_mem_adr_l1;
  wire [7:0] buf_mem_adr_l2;
  assign buf_mem_adr_l1 = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.buffer_current_mem_i.adr;
  assign buf_mem_adr_l2 = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.buffer_current_mem_i.adr;

  // === Dump dell'array `mem` di buffer_current_mem (256 × 16 bit) ========
  // iverilog non dumpa gli array di memoria con `$dumpvars(0, scope)`:
  // ogni cella va aggiunta esplicitamente. In gtkwave compaiono come
  //   ...buffer_current_mem_i.mem[0] .. mem[255]
  // sotto la gerarchia del SoC.
  parameter BUF_MEM_ROWS = 256;
  integer i_buf_mem;
  initial begin
    #1;  // attendo che la TB principale abbia aperto il VCD
    for (i_buf_mem = 0; i_buf_mem < BUF_MEM_ROWS; i_buf_mem = i_buf_mem + 1) begin
      $dumpvars(1, servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.buffer_current_mem_i.mem[i_buf_mem]);
      $dumpvars(1, servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.buffer_current_mem_i.mem[i_buf_mem]);
    end
  end

  // target da file (due numeri per ciascun valid: p1 atteso e p2 atteso)
  integer signed target_p1;
  integer signed target_p2;

  always @(posedge wb_clk) begin
    if (valid_snn) begin
      sample_idx <= sample_idx + 1;
      if(valid_label)
        $fwrite(f_label,"[%0d\n", label);
      // log corrente HW
      $fwrite(f_out,"[%0d,%0d],\n", $signed(p1), $signed(p2));
      $display("#[VALID #%0d  \tHW: p1=%0d  \tp2=%0d \tbuf_d_L1=%0d buf_d_L2=%0d]",
               sample_idx, $signed(p1), $signed(p2),
               $signed(buf_curr_d_l1), $signed(buf_curr_d_l2));

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

  // Conta i cicli in cui `en` di snn_lp e' alto (= cicli di streaming dall'encoder)
  wire    tb_en_snn  = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.en;
  integer tb_en_cnt  = 0;
  always @(posedge wb_clk)
    if (i_rst)         tb_en_cnt <= 0;
    else if (tb_en_snn) tb_en_cnt <= tb_en_cnt + 1;

`endif

endmodule
