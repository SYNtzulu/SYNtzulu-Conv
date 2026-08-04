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

   // 24 MHz: periodo 41.667 ns (mezzo periodo 20.833 ns), come il vecchio SB_HFOSC.
   // Prima i_clk era ignorato (osc. interno), quindi il #5 non contava; ora e' il clock reale.
   always  #20.833 i_clk <= !i_clk;
   initial #40 i_rst <= 1'b0;

   uart_decoder #(4000000) uart_decoder (q);

    wire wb_clk;
`ifndef PSIM
    assign wb_clk = servant_sim_i.soc_i.servant.wb_clk;
`else
    // post-synthesis: single clock domain, every flop of the netlist is
    // clocked by i_clk_i (the internal net driven by the i_clk input pad).
    assign wb_clk = servant_sim_i.soc_i.i_clk_i;
`endif

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
// Nome distinto per RTL e netlist, come gia' si fa col VCD: altrimenti una run
// post-sintesi sovrascrive in silenzio le finestre misurate in RTL e non si
// capisce piu' da dove vengono i numeri. Il target simulate_post_layout
// rinomina poi _ps in _pl, esattamente come fa con ps_tb_serv.vcd.
`ifndef PSIM
parameter POWER_WINDOW_FILE   = {"sim/results/",`PATH,"/power_windows.txt"};
`else
parameter POWER_WINDOW_FILE   = {"sim/results/",`PATH,"/power_windows_ps.txt"};
`endif

parameter MAX_ERRORS = 2;

integer i,j,k;
integer f_t_bin, f_out_bin;
integer f_out_target, f_out, f_label;
integer runtime_ns = 9000000;

initial begin
  // +nodump skips the waveform dump: on the post-synthesis netlist (>100k
  // cells) the VCD is several GB and dominates the run time.
  if (!$test$plusargs("nodump")) begin
`ifndef PSIM
    $dumpfile("tb_serv.vcd");
`else
    $dumpfile("ps_tb_serv.vcd");
`endif
    // +gatedump : dump ridotto per guardare il clock gating. Il dump completo
    // su una simulazione lunga abbastanza da contenere piu' cicli di sleep
    // produce un VCD da GB e domina il tempo di esecuzione. Qui si prendono
    // solo i segnali del solo livello top del tb (i_clk, wb_clk, clk_en_probe,
    // class_valid_probe, valid_snn, p1, p2) piu' l'intero clkgen, che e' dove
    // stanno clk_en, gate_arm, gate_pend, gate_cnt, irq_sync e slow_tick.
    if ($test$plusargs("gatedump")) begin
      $dumpvars(0,servant_tb);
`ifndef PSIM
      $dumpvars(0,servant_sim_i.soc_i.servant.clkgen);
`endif
    end else begin
      $dumpvars(0,servant_tb);
    end
  end

  f_out_target = $fopen(TARGET_FILE,"r");
  f_out        = $fopen(OUTPUT_FILE_TARGET,"w");
  f_label       = $fopen(LABEL_FILE_OUTPUT,"w");

  // quale occorrenza di idle/inferenza finisce nel riepilogo: +window=N
  dummy = $value$plusargs("window=%d", window_sel);

  // Durata simulata. Il default resta quello storico (9 ms), ma per le
  // finestre di potenza serve di piu': il solo caricamento di pesi e
  // istruzioni via SPI occupa i primi ~6.3 ms, e un ciclo campione+inferenza
  // ne vale altri ~2. Con +runtime_ns=25000000 si vedono 4-5 cicli completi.
  dummy = $value$plusargs("runtime_ns=%d", runtime_ns);

`ifndef PSIM
  trace_on = $test$plusargs("gatetrace");
`endif

  #20000
  buttons = 0;
  #runtime_ns;

  //#2000000000;

  $fclose(f_out);
  $fclose(f_out_target);
  $fclose(f_out_bin);
  $fclose(f_t_bin);

  report_power_windows;

  //$display("#[VERIFICATE #%0d  CORRENTI\nERRORI TOTALI: #%0d]", sample_idx, errors_snn_inference);
  $finish;
end

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

`ifndef PSIM
  // ---------------------------------------------------------------------
  //  RTL: normal hierarchical paths
  // ---------------------------------------------------------------------
  assign pooling_enable = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.pooling_enable;

  assign valid_snn = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.en_shift[3];
  assign p1        = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in;
  assign p2        = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in;

  assign valid_label = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.output_buffer_wr_en;
  assign label = servant_sim_i.soc_i.servant.inst_servant_syntzulu.mosquito.output_buffer_din;
`else
  // ---------------------------------------------------------------------
  //  POST-SYNTHESIS netlist (1_synth.v)
  //
  //  yosys flattens the design into the single module "soc" but keeps the
  //  original names, turned into ESCAPED identifiers and bit-blasted:
  //      \servant.inst_servant_syntzulu.mosquito. ... .comparator_in[15]
  //  so every probe has to be bound one bit at a time (note the space that
  //  closes each escaped identifier).
  //
  //  Only nets that SURVIVE synthesis can be probed, i.e. flop outputs.
  //  Purely combinational nets are gone:
  //    - pooling_enable  = (layer_type == 2'b10), and layer_type comes from
  //      instr[79:78] -> rebuilt here from instruction_memory.instruction,
  //      which is a register and is already marked (* keep *);
  //    - output_buffer_wr_en / output_buffer_din (label log only) have no
  //      equivalent register: label logging is disabled here.
  //  p1/p2 (comparator_in) are flop outputs and keep their name, so the
  //  inference check itself runs exactly as on RTL.
  //
  //  valid_snn: en_shift[3] survives only as the INSTANCE name of its flop
  //  ("...en_shift[3]$_DFF_PP0_"); yosys merged the net it drives with
  //  another one and kept the other name. To re-find it after a new
  //  synthesis run, grep the netlist for that instance and read its .Q().
  // ---------------------------------------------------------------------
  assign pooling_enable =  servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.instruction_memory.instruction[79]  &&
                          !servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.instruction_memory.instruction[78] ;

  assign valid_snn = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.fifo_i.potential_mem.ena ;

  assign valid_label = 1'b0;
  assign label       = 32'b0;

  assign p1[15] = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[15] ;
  assign p1[14] = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[14] ;
  assign p1[13] = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[13] ;
  assign p1[12] = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[12] ;
  assign p1[11] = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[11] ;
  assign p1[10] = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[10] ;
  assign p1[9]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[9] ;
  assign p1[8]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[8] ;
  assign p1[7]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[7] ;
  assign p1[6]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[6] ;
  assign p1[5]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[5] ;
  assign p1[4]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[4] ;
  assign p1[3]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[3] ;
  assign p1[2]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[2] ;
  assign p1[1]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[1] ;
  assign p1[0]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[0] ;

  assign p2[15] = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[15] ;
  assign p2[14] = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[14] ;
  assign p2[13] = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[13] ;
  assign p2[12] = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[12] ;
  assign p2[11] = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[11] ;
  assign p2[10] = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[10] ;
  assign p2[9]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[9] ;
  assign p2[8]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[8] ;
  assign p2[7]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[7] ;
  assign p2[6]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[6] ;
  assign p2[5]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[5] ;
  assign p2[4]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[4] ;
  assign p2[3]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[3] ;
  assign p2[2]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[2] ;
  assign p2[1]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[1] ;
  assign p2[0]  = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.mosquito.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.comparator_in[0] ;
`endif

  // ==========================================================================
  //  FINESTRE DI POTENZA : start_idle / end_idle / start_inference / end_inference
  //
  //  Servono due intervalli disgiunti su cui stimare la potenza:
  //
  //    IDLE       il clock gating e' attivo, clk_en = 0 in clk_gen_wb, quindi
  //               wb_clk e' fermo e commuta solo la logica sull'always-on i_clk
  //               (sincronizzatore di reset, prescaler, timer).
  //    INFERENCE  la rete sta macinando un campione: dal primo colpo di
  //               valid_snn fino a quando acc_snn_valid_mp segnala la classe
  //               pronta (e' il bit che il firmware polla su SYNTZULU_CLASS).
  //
  //  Il campionamento e' su i_clk, non su wb_clk: durante l'idle wb_clk e'
  //  fermo per definizione e un always @(posedge wb_clk) non vedrebbe mai la
  //  fine della finestra.
  //
  //  Entrambe le sonde sopravvivono alla sintesi (sono uscite di flop), quindi
  //  i path valgono anche in PSIM, li' come identificatori escaped.
  // ==========================================================================
  wire clk_en_probe;      // 1 = clock libero, 0 = gating attivo
  wire class_valid_probe; // classe pronta -> fine inferenza

`ifndef PSIM
  assign clk_en_probe      = servant_sim_i.soc_i.servant.clkgen.clk_en;
  assign class_valid_probe = servant_sim_i.soc_i.servant.inst_servant_syntzulu.acc_snn_valid_mp;
`else
  assign clk_en_probe      = servant_sim_i.soc_i.\servant.clkgen.clk_en ;
  assign class_valid_probe = servant_sim_i.soc_i.\servant.inst_servant_syntzulu.acc_snn_valid_mp ;
`endif

  // Quale occorrenza riportare nel riepilogo finale. La prima finestra dopo il
  // boot comprende il caricamento di pesi/istruzioni via SPI e non e'
  // rappresentativa, quindi il default e' la seconda.
  integer window_sel = 2;

  integer f_win;
  integer idle_n  = 0;
  integer infer_n = 0;

  real start_idle      = -1.0;
  real end_idle        = -1.0;
  real start_inference = -1.0;
  real end_inference   = -1.0;

  real    t_idle_open;
  real    t_infer_open;
  reg     idle_open  = 1'b0;
  reg     infer_open = 1'b0;

  reg clk_en_q      = 1'b1;
  reg valid_snn_q   = 1'b0;
  reg class_valid_q = 1'b0;

  always @(posedge i_clk) begin
    clk_en_q      <= clk_en_probe;
    valid_snn_q   <= valid_snn;
    class_valid_q <= class_valid_probe;

    // ---- finestra di IDLE : delimitata dai fronti di clk_en ----
    if (clk_en_q === 1'b1 && clk_en_probe === 1'b0) begin
      t_idle_open <= $realtime;
      idle_open   <= 1'b1;
      $display("#[GATE ON   t=%0.3f ns  clock fermo]", $realtime);
    end
    if (clk_en_q === 1'b0 && clk_en_probe === 1'b1 && idle_open) begin
      idle_open <= 1'b0;
      idle_n     = idle_n + 1;
      $display("#[IDLE      #%0d  start=%0.3f ns  end=%0.3f ns  dur=%0.3f ns]",
               idle_n, t_idle_open, $realtime, $realtime - t_idle_open);
      if (idle_n == window_sel) begin
        start_idle = t_idle_open;
        end_idle   = $realtime;
      end
    end

    // ---- finestra di INFERENZA : primo valid_snn -> classe pronta ----
    if (!infer_open && valid_snn === 1'b1 && valid_snn_q === 1'b0) begin
      t_infer_open <= $realtime;
      infer_open   <= 1'b1;
    end
    if (infer_open && class_valid_probe === 1'b1 && class_valid_q === 1'b0) begin
      infer_open <= 1'b0;
      infer_n     = infer_n + 1;
      $display("#[INFERENCE #%0d  start=%0.3f ns  end=%0.3f ns  dur=%0.3f ns]",
               infer_n, t_infer_open, $realtime, $realtime - t_infer_open);
      if (infer_n == window_sel) begin
        start_inference = t_infer_open;
        end_inference   = $realtime;
      end
    end
  end

  // ==========================================================================
  //  TRACCIA DEL GATING (+gatetrace)
  //
  //  Stampa ogni fronte dei quattro segnali che decidono se il core dorme.
  //  Serve a capire perche' il gate si chiude una volta e poi non piu': la
  //  scrittura Wishbone che arma il gate e' ancora in volo quando il clock si
  //  ferma, quindi wb_clk_cyc (e con lui gate_arm) resta alto per tutto il
  //  sonno e si sovrappone al risveglio.
  //
  //  Solo RTL: in PSIM questi nodi interni non hanno tutti un equivalente.
  // ==========================================================================
`ifndef PSIM
  wire dbg_gate_arm  = servant_sim_i.soc_i.servant.clkgen.gate_arm;
  wire dbg_irq_sync  = servant_sim_i.soc_i.servant.clkgen.irq_sync;
  wire dbg_timer_irq = servant_sim_i.soc_i.servant.timer_irq;
  wire dbg_cyc       = servant_sim_i.soc_i.servant.wb_clk_cyc;
  wire dbg_tcyc      = servant_sim_i.soc_i.servant.wb_timer_cyc;
  wire dbg_twe       = servant_sim_i.soc_i.servant.wb_timer_we;
  wire dbg_dcyc      = servant_sim_i.soc_i.servant.wb_dbus_cyc;
  wire dbg_dack      = servant_sim_i.soc_i.servant.wb_dbus_ack;

  reg trace_on = 1'b0;
  reg dbg_ga_q, dbg_is_q, dbg_ti_q, dbg_cy_q, dbg_ce_q;
  reg dbg_tc_q, dbg_tw_q, dbg_dc_q, dbg_da_q;

  always @(posedge i_clk) begin
    dbg_ga_q <= dbg_gate_arm;
    dbg_is_q <= dbg_irq_sync;
    dbg_ti_q <= dbg_timer_irq;
    dbg_cy_q <= dbg_cyc;
    dbg_ce_q <= clk_en_probe;
    dbg_tc_q <= dbg_tcyc;
    dbg_tw_q <= dbg_twe;
    dbg_dc_q <= dbg_dcyc;
    dbg_da_q <= dbg_dack;

    if (trace_on) begin
      if (dbg_tcyc !== dbg_tc_q)
        $display("  [trace %0.3f] timer_cyc   -> %b", $realtime, dbg_tcyc);
      if (dbg_twe  !== dbg_tw_q)
        $display("  [trace %0.3f] timer_we    -> %b", $realtime, dbg_twe);
      if (dbg_dcyc !== dbg_dc_q)
        $display("  [trace %0.3f] dbus_cyc    -> %b", $realtime, dbg_dcyc);
      if (dbg_dack !== dbg_da_q)
        $display("  [trace %0.3f] dbus_ack    -> %b", $realtime, dbg_dack);
      if (dbg_timer_irq  !== dbg_ti_q)
        $display("  [trace %0.3f] timer_irq   -> %b", $realtime, dbg_timer_irq);
      if (dbg_irq_sync   !== dbg_is_q)
        $display("  [trace %0.3f] irq_sync    -> %b", $realtime, dbg_irq_sync);
      if (dbg_cyc        !== dbg_cy_q)
        $display("  [trace %0.3f] clkgen_cyc  -> %b", $realtime, dbg_cyc);
      if (dbg_gate_arm   !== dbg_ga_q)
        $display("  [trace %0.3f] gate_arm    -> %b", $realtime, dbg_gate_arm);
      if (clk_en_probe   !== dbg_ce_q)
        $display("  [trace %0.3f] clk_en      -> %b", $realtime, clk_en_probe);
    end
  end
`endif

  task report_power_windows;
    begin
      $display("");
      $display("=== FINESTRE DI POTENZA (occorrenza #%0d) ===", window_sel);
      // Una finestra ancora aperta a fine simulazione non e' un errore: vuol
      // dire solo che il tempo simulato e' finito prima della sveglia. Va
      // detto, altrimenti "0 finestre" si legge come "il gating non entra".
      if (idle_open)
        $display("nota: gating entrato a %0.3f ns e ancora attivo a fine simulazione (allunga con +runtime_ns=N per vedere la sveglia)", t_idle_open);
      if (infer_open)
        $display("nota: inferenza iniziata a %0.3f ns e non ancora conclusa a fine simulazione",
                 t_infer_open);
      if (start_idle < 0.0)
        $display("start_idle      = n/d   (finestre di idle viste: %0d - il gating non e' mai entrato?)", idle_n);
      else begin
        $display("start_idle      = %0.3f ns", start_idle);
        $display("end_idle        = %0.3f ns", end_idle);
      end
      if (start_inference < 0.0)
        $display("start_inference = n/d   (inferenze complete viste: %0d)", infer_n);
      else begin
        $display("start_inference = %0.3f ns", start_inference);
        $display("end_inference   = %0.3f ns", end_inference);
      end

      f_win = $fopen(POWER_WINDOW_FILE, "w");
      if (f_win) begin
        $fwrite(f_win, "start_idle      %0.3f\n", start_idle);
        $fwrite(f_win, "end_idle        %0.3f\n", end_idle);
        $fwrite(f_win, "start_inference %0.3f\n", start_inference);
        $fwrite(f_win, "end_inference   %0.3f\n", end_inference);
        $fclose(f_win);
      end
    end
  endtask

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
        report_power_windows;
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


endmodule
