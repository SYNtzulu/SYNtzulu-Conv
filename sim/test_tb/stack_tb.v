`timescale 1ns/1ps

module tb_compare_stacks;

  // ---------- Parametri di test (puoi modificarli facilmente)
  localparam integer MAX_SYNAPSES    = 64;
  localparam integer DEPTH           = (MAX_SYNAPSES/4);     // 16
  localparam integer DATA_WIDTH      = clogb2(DEPTH-1);      // larghezza indirizzi
  localparam real    CLK_PERIOD_NS   = 10.0;                 // 100 MHz

  // ---------- Clock & Reset
  reg clk = 0;
  always #(CLK_PERIOD_NS/2.0) clk = ~clk;

  reg rst = 1;

  // ---------- Stimoli comuni
  reg  [DATA_WIDTH-1:0] din;
  // Per gli stack "shift-register"
  reg  wr_en_1, wr_en_2;
  reg  clear_1, clear_2;
  reg  stream_out_1, stream_out_2;

  // Per lo stack_bram a 2 banchi
  reg  wr_en_bram;
  reg  clear_bram;
  reg  rd_en_bram;
  reg  layer_counter;  // 1 -> banca 1, 0 -> banca 2

  // ---------- Uscite / monitor
  wire [DATA_WIDTH-1:0] dout_sr_1, dout_sr_2;
  wire done_sr_1, done_sr_2;
  wire [clogb2(DEPTH-1)-1:0] active_sr_1, active_sr_2;
  wire empty_sr_1, empty_sr_2;

  wire [DATA_WIDTH-1:0] dout_bram_1, dout_bram_2;
  wire done_bram_1, done_bram_2;
  wire [clogb2(DEPTH-1)-1:0] active_bram_1, active_bram_2;
  wire empty_bram_1, empty_bram_2;
  reg [DATA_WIDTH-1:0] tmp_val;

  // ---------- DUTs: due stack “shift-register”
  stack #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(DEPTH)
  ) u_stack_1 (
    .clk(clk), .rst(rst),
    .din(din),
    .wr_en(wr_en_1),
    .clear(clear_1),
    .stream_out(stream_out_1),
    .dout(dout_sr_1),
    .done(done_sr_1),
    .active_entries(active_sr_1),
    .empty(empty_sr_1)
  );

  stack #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(DEPTH)
  ) u_stack_2 (
    .clk(clk), .rst(rst),
    .din(din),
    .wr_en(wr_en_2),
    .clear(clear_2),
    .stream_out(stream_out_2),
    .dout(dout_sr_2),
    .done(done_sr_2),
    .active_entries(active_sr_2),
    .empty(empty_sr_2)
  );

  // ---------- DUT: stack_bram a 2 banchi
  stack_bram #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(DEPTH)
  ) u_stack_bram (
    .clk(clk), .rst(rst),
    .layer_counter(layer_counter),
    .din(din),
    .wr_en(wr_en_bram),
    .clear(clear_bram),
    .rd_en(rd_en_bram),
    .dout(dout_bram_1), 
    .done_1(done_bram_1), .done_2(done_bram_2),
    .active_entries(active_bram_1),
    .empty_1(empty_bram_1), .empty_2(empty_bram_2)
  );

  // ---------- Dump per waveform
  initial begin
        $dumpfile("tb_stack.vcd"); 
    $dumpvars(10, tb_compare_stacks);
  end

  // ---------- Sequenza di test
  integer i;

  initial begin
    // reset sincrono
    rst = 1;
    din = '0;

    wr_en_1 = 0; wr_en_2 = 0;
    clear_1 = 0; clear_2 = 0;
    stream_out_1 = 0; stream_out_2 = 0;

    wr_en_bram = 0; clear_bram = 0; rd_en_bram = 0; layer_counter = 0;

    repeat (5) @(posedge clk);
    rst = 0;
    @(posedge clk);

    // ------------------ PHASE A: scrivo su banca 1 (layer_counter=1)
    $display("\n=== PHASE A: WRITE on BANK1 / LAYER=1 ===");
    layer_counter <= 1'b1;
    for (i = 0; i < 6; i = i+1) begin
      din <= i[DATA_WIDTH-1:0] + 8;     // valori 8..13
      wr_en_1 <= 1'b1;                  // scrive nello stack_1
      wr_en_bram <= 1'b1;               // scrive nel banco1 del BRAM
      @(posedge clk);
    end
    wr_en_1 <= 1'b0;
    wr_en_bram <= 1'b0;
    @(posedge clk);

    // Stream out BANK1
    $display("=== PHASE A: STREAM OUT BANK1 ===");
    stream_out_1 <= 1'b1;               // avvia stream nello stack_1
    rd_en_bram   <= 1'b1;               // avvia lettura BRAM (banco1)
    @(posedge clk);
    stream_out_1 <= 1'b0;
    // tengo rd_en_bram alto per tutta la “scarica”
    repeat (10) begin
      @(posedge clk);
      $display("t=%0t  SR1:dout=%0d done=%0b  |  BRAM1:dout=%0d done=%0b",
               $time, dout_sr_1, done_sr_1, dout_bram_1, done_bram_1);
    end
    rd_en_bram <= 1'b0;

    // Clear BANK1
    $display("=== PHASE A: CLEAR BANK1 ===");
    clear_1 <= 1'b1;
    clear_bram <= 1'b1;
    @(posedge clk);
    clear_1 <= 1'b0;
    clear_bram <= 1'b0;
    @(posedge clk);

    // ------------------ PHASE B: scrivo su banca 2 (layer_counter=0)
    $display("\n=== PHASE B: WRITE on BANK2 / LAYER=0 ===");
    layer_counter <= 1'b0;
    for (i = 0; i < 5; i = i+1) begin
      din <= i[DATA_WIDTH-1:0] + 20;    // valori 20..24
      wr_en_2 <= 1'b1;                  // scrive nello stack_2
      wr_en_bram <= 1'b1;               // scrive nel banco2 del BRAM
      @(posedge clk);
    end
    wr_en_2 <= 0;
    wr_en_bram <= 0;
    @(posedge clk);

    // Stream out BANK2
    $display("=== PHASE B: STREAM OUT BANK2 ===");
    stream_out_2 <= 1'b1;
    rd_en_bram   <= 1'b1;
    @(posedge clk);
    stream_out_2 <= 1'b0;

    repeat (10) begin
      @(posedge clk);
      $display("t=%0t  SR2:dout=%0d done=%0b  |  BRAM2:dout=%0d done=%0b",
               $time, dout_sr_2, done_sr_2, dout_bram_2, done_bram_2);
    end
    rd_en_bram <= 1'b0;

    // ------------------ PHASE C: interleave (scrivo banco1 e 2 alternati)
    $display("\n=== PHASE C: INTERLEAVE WRITES (B1/B2) ===");
    for (i = 0; i < 4; i = i+1) begin
      // banco1
      layer_counter <= 1'b1;
      
    tmp_val = 30 + i;
    din <= tmp_val;


      wr_en_1 <= 1; wr_en_bram <= 1;
      @(posedge clk);
      wr_en_1 <= 0; wr_en_bram <= 0;

      // banco2
      layer_counter <= 1'b0;

tmp_val = 40 + i;
din <= tmp_val;


      wr_en_2 <= 1; wr_en_bram <= 1;
      @(posedge clk);
      wr_en_2 <= 0; wr_en_bram <= 0;
    end
    @(posedge clk);

    // stream out banco1 e banco2 uno dopo l’altro
    $display("=== PHASE C: STREAM OUT BANK1 ===");
    layer_counter <= 1'b1;
    stream_out_1 <= 1; rd_en_bram <= 1;
    @(posedge clk);
    stream_out_1 <= 0;
    repeat (10) begin
      @(posedge clk);
      $display("t=%0t  SR1:dout=%0d done=%0b  |  BRAM1:dout=%0d done=%0b",
               $time, dout_sr_1, done_sr_1, dout_bram_1, done_bram_1);
    end
    rd_en_bram <= 0;

    $display("=== PHASE C: STREAM OUT BANK2 ===");
    layer_counter <= 1'b0;
    stream_out_2 <= 1; rd_en_bram <= 1;
    @(posedge clk);
    stream_out_2 <= 0;
    repeat (10) begin
      @(posedge clk);
      $display("t=%0t  SR2:dout=%0d done=%0b  |  BRAM2:dout=%0d done=%0b",
               $time, dout_sr_2, done_sr_2, dout_bram_2, done_bram_2);
    end
    rd_en_bram <= 0;

    $display("\n=== TEST FINITO ===");
    #50;
    $finish;
  end

  // --------- helper: clog2 identico ai tuoi moduli
  function integer clogb2;
    input integer depth;
    begin
      for (clogb2 = 0; depth > 0; clogb2 = clogb2 + 1)
        depth = depth >> 1;
    end
  endfunction

endmodule
