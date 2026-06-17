`timescale 1ns / 1ps
`default_nettype none

`include "rtl/define.v"
`include `CONFIG_PATH

// ============================================================================
//  syntzulu_tb_mnist_snn_lp
//  ----------------------------------------------------------------------------
//  Testbench stand-alone equivalente a syntzulu_tb_mnist.sv ma che istanzia
//  SOLO il modulo snn_lp (niente Syntzulu top, niente encoder).
//
//  Differenze rispetto al TB completo:
//     • niente encoding_slot: gli ingressi s1_encoding / s2_encoding vengono
//       letti direttamente da due file di testo, un bit per riga:
//          sim/mem/mnist/input_even.txt  -> s1_encoding
//          sim/mem/mnist/input_odd.txt   -> s2_encoding
//       (formato $readmemb: token '0' / '1' separati da whitespace)
//     • input_buffer_valid è pilotato dal TB tenendolo alto per la durata
//       dello streaming del frame, come fa valid_encoding nell'encoder MNIST
//       reale (encoding_spike_buffer). Il rising edge genera
//       start_instruction dentro snn_lp.
//
//  I 4 banchi pesi vengono caricati con lo stesso pattern del TB completo a
//  partire da sim/mem/mnist/flash.txt (offset W1..W4). Le memorie di
//  decay/threshold sono autoinizializzate via $readmemh dentro layer_lp
//  (path cablati in snn_lp.sv: "mnist/decay_thr_1.txt" / "..._2.txt"),
//  quindi la sim DEVE essere lanciata dalla root del progetto.
// ============================================================================

module syntzulu_tb_mnist_snn_lp;

    // ========================================================================
    //  PARAMETRI DI CONFIGURAZIONE
    // ========================================================================

    // ---- Path dei file (relativi alla root del progetto) -------------------
    //  Tutti i path dei dati derivano da `PATH (definito in rtl/define.v):
    //  basta cambiare quella macro per puntare a un'altra cartella dataset.
    localparam FLASH_FILE   = {`PATH, "/flash.txt"};         // pesi (formato $readmemh)
    localparam S1_FILE      = {`PATH, "/input_even.txt"};    // bit s1_encoding (uno per riga)
    localparam S2_FILE      = {`PATH, "/input_odd.txt"};     // bit s2_encoding (uno per riga)
    localparam INSTR_FILE   = {`PATH, "/instruction.hex"};   // istruzioni
    localparam TARGET_FILE  = {`PATH, "/snn_inference.txt"}; // riferimento p1/p2
    localparam OUTPUT_FILE  = {`PATH, "/inference_out.txt"}; // dump correnti HW
    localparam VCD_FILE     = "syntzulu_tb_mnist_snn_lp.vcd";           // waveform

    // ---- Parametri snn_lp (specchio servant_syntzulu MNIST) ---------------
    localparam DW               = `DW;
    localparam WIDTH            = 16;
    localparam CHANNELS         = `INPUT_CHANNELS; // 32
    localparam TIME_STEPS       = `TIME_STEPS;     // 10
    localparam MAX_NEURONS      = 128;
    localparam MAX_SYNAPSES     = 256;
    localparam LAYERS           = 8;
    localparam MAX_DECAY        = 4096;
    localparam MAX_THRESHOLD    = 65536;
    localparam INSTR_WIDTH      = 80;
    localparam WEIGHT_DEPTH_12  = 8192;
    localparam WEIGHT_DEPTH_34  = 8192;

    // ---- Layout flash (solo regione pesi, no sample) ----------------------
    localparam W1_OFFSET        = 0;
    localparam W2_OFFSET        = W1_OFFSET + WEIGHT_DEPTH_12;
    localparam W3_OFFSET        = W2_OFFSET + WEIGHT_DEPTH_12;
    localparam W4_OFFSET        = W3_OFFSET + WEIGHT_DEPTH_12;
    localparam WORDS_PER_BANK   = WEIGHT_DEPTH_12 / 2;       // 4096
    localparam FLASH_BYTES      = 4 * WEIGHT_DEPTH_12;       // 32768

    // ---- Stream s1/s2 -----------------------------------------------------
    //   Input feature map: INPUT_H × INPUT_W × INPUT_C  (1 bit per spike).
    //   Streammati a pair (s1,s2) per ciclo
    //      ->  BITS_PER_FRAME = H*W*C / 2  pair/frame.
    //   Setup attuale: 16 × 16 × 16  =  4096 spike  ->  2048 pair/frame.
    localparam INPUT_H          = 16;
    localparam INPUT_W          = 16;
    localparam INPUT_C          = 16;
    localparam BITS_PER_FRAME   = (INPUT_H * INPUT_W * INPUT_C) / 2;   // 2048
    localparam NUM_FRAMES       = TIME_STEPS;                          // 10
    localparam MAX_BITS         = BITS_PER_FRAME * NUM_FRAMES;

    // ---- Tuning -----------------------------------------------------------
    localparam MAX_ERRORS         = 10;
    localparam RESET_CYCLES_HIGH  = 10;
    localparam RESET_CYCLES_LOW   = 5;
    localparam POST_WEIGHTS_CYCLES= 50;
    localparam INTER_FRAME_CYCLES = 20000;
    localparam DRAIN_FINAL_CYCLES = 50000;

    // ========================================================================
    //  CLOCK & RESET
    // ========================================================================
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;   // 100 MHz

    // ========================================================================
    //  STIMOLI snn_lp
    // ========================================================================
    reg                                  en                 = 1'b0;
    reg                                  s1_encoding        = 1'b0;
    reg                                  s2_encoding        = 1'b0;
    reg                                  input_buffer_valid = 1'b0;
    reg                                  reset_potential    = 1'b0;

    // Porte di scrittura weight memory
    reg                                  w1_wren = 1'b0, w1_ena = 1'b0;
    reg [clogb2(WEIGHT_DEPTH_12-1)-1:0]  w1_addr = '0;
    reg [15:0]                           w1_data = 16'd0;
    reg                                  w2_wren = 1'b0, w2_ena = 1'b0;
    reg [clogb2(WEIGHT_DEPTH_12-1)-1:0]  w2_addr = '0;
    reg [15:0]                           w2_data = 16'd0;
    reg                                  w3_wren = 1'b0, w3_ena = 1'b0;
    reg [clogb2(WEIGHT_DEPTH_34-1)-1:0]  w3_addr = '0;
    reg [15:0]                           w3_data = 16'd0;
    reg                                  w4_wren = 1'b0, w4_ena = 1'b0;
    reg [clogb2(WEIGHT_DEPTH_34-1)-1:0]  w4_addr = '0;
    reg [15:0]                           w4_data = 16'd0;

    // Uscite snn_lp
    wire                    valid;
    wire                    valid_spike;
    wire [3:0]              spike_out;
    wire                    integrated_neuron;
    wire signed [WIDTH-1:0] voltage_1;
    wire signed [WIDTH-1:0] voltage_2;
    wire                    s1_out, s2_out;
    wire                    last_layer;
    wire [7:0]              integrated_neurons_cnt;

    // ========================================================================
    //  DUT  (solo snn_lp)
    // ========================================================================
    snn_lp #(
        .WIDTH           (WIDTH),
        .MAX_SYNAPSES    (MAX_SYNAPSES),
        .MAX_NEURONS     (MAX_NEURONS),
        .LAYERS          (LAYERS),
        .MAX_DECAY       (MAX_DECAY),
        .MAX_THRESHOLD   (MAX_THRESHOLD),
        .INSTR_WIDTH     (INSTR_WIDTH),
        .INSTR_FILE      (INSTR_FILE),
        .DATA_DIR        (`PATH),  // cartella dati per decay_thr_*.txt (da `PATH)
        .WEIGHTS_FILE_1  (""),    // weight mem caricate a runtime via porte
        .WEIGHTS_FILE_2  (""),
        .WEIGHTS_FILE_3  (""),
        .WEIGHTS_FILE_4  (""),
        .WEIGHT_DEPTH_12 (WEIGHT_DEPTH_12),
        .WEIGHT_DEPTH_34 (WEIGHT_DEPTH_34)
    ) dut (
        .clk              (clk),
        .rst              (rst),
        .en               (en),
        .s1_encoding      (s1_encoding),
        .s2_encoding      (s2_encoding),
        .reset_potential  (reset_potential),

        .valid            (valid),
        .valid_spike      (valid_spike),
        .spike_out        (spike_out),
        .integrated_neuron(integrated_neuron),

        // weight memory L1
        .weight_mem_L1_wren    (w1_wren),
        .weight_mem_L1_wr_addr (w1_addr),
        .weight_mem_L1_data_in (w1_data),
        .weight_mem_L1_ena     (w1_ena),
        // weight memory L2
        .weight_mem_L2_wren    (w2_wren),
        .weight_mem_L2_wr_addr (w2_addr),
        .weight_mem_L2_data_in (w2_data),
        .weight_mem_L2_ena     (w2_ena),
        // weight memory L3
        .weight_mem_L3_wren    (w3_wren),
        .weight_mem_L3_wr_addr (w3_addr),
        .weight_mem_L3_data_in (w3_data),
        .weight_mem_L3_ena     (w3_ena),
        // weight memory L4
        .weight_mem_L4_wren    (w4_wren),
        .weight_mem_L4_wr_addr (w4_addr),
        .weight_mem_L4_data_in (w4_data),
        .weight_mem_L4_ena     (w4_ena),

        .voltage_1              (voltage_1),
        .voltage_2              (voltage_2),
        .s1                     (s1_out),
        .s2                     (s2_out),
        .last_layer             (last_layer),
        .integrated_neurons_cnt (integrated_neurons_cnt),
        .input_buffer_valid     (input_buffer_valid)
    );

    // ========================================================================
    //  SONDE  (gerarchia senza il prefisso .snn_lp_i. del TB completo)
    // ========================================================================
    wire signed [15:0] p1        = dut.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.output_new;
    wire signed [15:0] p2        = dut.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.output_new;
    wire               valid_snn = dut.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.valid_fifo;

    wire signed [15:0] buf_curr_d_l1 = dut.layer_lp_l1_i.neuron_lp_i.Voltage_i.buffer_current_d;
    wire signed [15:0] buf_curr_d_l2 = dut.layer_lp_l2_i.neuron_lp_i.Voltage_i.buffer_current_d;

    // Sonde sugli spike-mem write valid (utile a debug)
    wire tb_valid_s1_mem = dut.spike_mem.valid_s1;
    wire tb_valid_s2_mem = dut.spike_mem.valid_s2;

    // ------------------------------------------------------------------------
    //  Sonde conv: gli anded_weights sono array unpacked interni a conv.sv,
    //  che $dumpvars NON dumpa automaticamente. Li aliaso qui su wire scalari
    //  cosi' compaiono nel VCD. conv ha DATA_WIDTH = WEIGHT = 8 -> [7:0].
    // ------------------------------------------------------------------------
    // Layer 1
    wire [3:0]        l1_conv_spikes      = dut.layer_lp_l1_i.conv_i.spikes;
    wire signed [7:0] l1_anded_a0         = dut.layer_lp_l1_i.conv_i.anded_weights_a[0];
    wire signed [7:0] l1_anded_a1         = dut.layer_lp_l1_i.conv_i.anded_weights_a[1];
    wire signed [7:0] l1_anded_b0         = dut.layer_lp_l1_i.conv_i.anded_weights_b[0];
    wire signed [7:0] l1_anded_b1         = dut.layer_lp_l1_i.conv_i.anded_weights_b[1];
    // Layer 2
    wire [3:0]        l2_conv_spikes      = dut.layer_lp_l2_i.conv_i.spikes;
    wire signed [7:0] l2_anded_a0         = dut.layer_lp_l2_i.conv_i.anded_weights_a[0];
    wire signed [7:0] l2_anded_a1         = dut.layer_lp_l2_i.conv_i.anded_weights_a[1];
    wire signed [7:0] l2_anded_b0         = dut.layer_lp_l2_i.conv_i.anded_weights_b[0];
    wire signed [7:0] l2_anded_b1         = dut.layer_lp_l2_i.conv_i.anded_weights_b[1];

    // ========================================================================
    //  LOAD WEIGHTS (uguale al TB completo)
    // ========================================================================
    reg [7:0] flash_mem [0:FLASH_BYTES-1];

    initial begin : load_flash
        integer i;
        for (i = 0; i < FLASH_BYTES; i = i + 1) flash_mem[i] = 8'h00;
        $readmemh(FLASH_FILE, flash_mem);
        $display("[TB] Flash pesi caricato (%0d byte)", FLASH_BYTES);
    end

    task automatic load_weight_mem;
        input integer which;
        input integer base_offset;
        integer i;
        reg [15:0] word;
        begin
            $display("[TB] Carico WEIGHT_MEM_L%0d (flash byte %0d..%0d, %0d word)",
                     which, base_offset,
                     base_offset + 2*WORDS_PER_BANK - 1, WORDS_PER_BANK);

            for (i = 0; i < WORDS_PER_BANK; i = i + 1) begin
                word = {flash_mem[base_offset + 2*i],
                        flash_mem[base_offset + 2*i + 1]};
                @(posedge clk);
                case (which)
                    1: begin w1_wren <= 1'b1; w1_ena <= 1'b1; w1_addr <= i[12:0]; w1_data <= word; end
                    2: begin w2_wren <= 1'b1; w2_ena <= 1'b1; w2_addr <= i[12:0]; w2_data <= word; end
                    3: begin w3_wren <= 1'b1; w3_ena <= 1'b1; w3_addr <= i[12:0]; w3_data <= word; end
                    4: begin w4_wren <= 1'b1; w4_ena <= 1'b1; w4_addr <= i[12:0]; w4_data <= word; end
                endcase
            end

            @(posedge clk);
            w1_wren <= 1'b0; w1_ena <= 1'b0;
            w2_wren <= 1'b0; w2_ena <= 1'b0;
            w3_wren <= 1'b0; w3_ena <= 1'b0;
            w4_wren <= 1'b0; w4_ena <= 1'b0;
        end
    endtask

    // ========================================================================
    //  CARICAMENTO STREAM s1 / s2 DAI FILE
    //  ------------------------------------------------------------------------
    //  Formato atteso: un bit ('0' o '1') per riga, separati da whitespace.
    //  $fscanf("%b") tollera spazi/newline e ignora i token non riconosciuti.
    // ========================================================================
    reg s1_bits [0:MAX_BITS-1];
    reg s2_bits [0:MAX_BITS-1];
    integer s1_count, s2_count, total_bits;

    task automatic load_spike_files;
        integer f1, f2, i, c;
        reg     bit_val;
        begin
            for (i = 0; i < MAX_BITS; i = i + 1) begin
                s1_bits[i] = 1'b0;
                s2_bits[i] = 1'b0;
            end

            // -- s1 --
            f1 = $fopen(S1_FILE, "r");
            if (f1 == 0) begin
                $display("[TB] ERRORE: impossibile aprire %s", S1_FILE);
                $finish;
            end
            i = 0;
            while (!$feof(f1) && i < MAX_BITS) begin
                c = $fscanf(f1, "%b\n", bit_val);
                if (c == 1) begin
                    s1_bits[i] = bit_val;
                    i = i + 1;
                end
            end
            s1_count = i;
            $fclose(f1);

            // -- s2 --
            f2 = $fopen(S2_FILE, "r");
            if (f2 == 0) begin
                $display("[TB] ERRORE: impossibile aprire %s", S2_FILE);
                $finish;
            end
            i = 0;
            while (!$feof(f2) && i < MAX_BITS) begin
                c = $fscanf(f2, "%b\n", bit_val);
                if (c == 1) begin
                    s2_bits[i] = bit_val;
                    i = i + 1;
                end
            end
            s2_count = i;
            $fclose(f2);

            total_bits = (s1_count < s2_count) ? s1_count : s2_count;
            $display("[TB] Letti s1=%0d bit, s2=%0d bit  ->  uso %0d bit (%0d frame da %0d bit)",
                     s1_count, s2_count, total_bits,
                     total_bits / BITS_PER_FRAME, BITS_PER_FRAME);

            if (total_bits < NUM_FRAMES * BITS_PER_FRAME)
                $display("[TB] WARNING: bit insufficienti per %0d frame (servono %0d). I bit mancanti restano 0.",
                         NUM_FRAMES, NUM_FRAMES * BITS_PER_FRAME);
        end
    endtask

    // ========================================================================
    //  TASK: feed_frame
    //  ------------------------------------------------------------------------
    //  Streamma BITS_PER_FRAME pair (s1,s2) verso snn_lp, replicando ciò che
    //  fa encoding_spike_buffer quando il suo buffer si riempie:
    //     • en (= valid_encoding lato encoder) alto per tutta la durata
    //     • input_buffer_valid (= valid_encoding lato snn_lp) idem, in modo
    //       che il rising edge generi start_instruction.
    //  Tra un frame e il successivo entrambi tornano a 0, cosicché la nuova
    //  salita riavvii start_instruction per il frame seguente.
    // ========================================================================
    task automatic feed_frame;
        input integer base_idx;
        integer k;
        begin
            for (k = 0; k < BITS_PER_FRAME; k = k + 1) begin
                @(posedge clk);
                en                 <= 1'b1;
                input_buffer_valid <= 1'b1;
                s1_encoding        <= s1_bits[base_idx + k];
                s2_encoding        <= s2_bits[base_idx + k];
            end
            @(posedge clk);
            en                 <= 1'b0;
            input_buffer_valid <= 1'b0;
            s1_encoding        <= 1'b0;
            s2_encoding        <= 1'b0;
        end
    endtask

    // ========================================================================
    //  CONFRONTO ONLINE vs TARGET (identico al TB completo)
    // ========================================================================
    integer        f_out, f_tgt, dummy;
    integer signed t1, t2;
    integer        sample_idx = 0;
    integer        errors     = 0;

    always @(posedge clk) begin
        if (!rst && valid_snn) begin
            sample_idx <= sample_idx + 1;

            $fwrite(f_out, "[%0d,%0d],\n", $signed(p1), $signed(p2));
            $display("#[VALID #%0d  HW: p1=%0d  p2=%0d  buf_d_L1=%0d  buf_d_L2=%0d]",
                     sample_idx, $signed(p1), $signed(p2),
                     $signed(buf_curr_d_l1), $signed(buf_curr_d_l2));

            if (!$feof(f_tgt)) dummy = $fscanf(f_tgt, "%d\n", t1); else t1 = 0;
            if (!$feof(f_tgt)) dummy = $fscanf(f_tgt, "%d\n", t2); else t2 = 0;

            if (t1 !== $signed(p1)) begin
                errors = errors + 1;
                $display("#ERR p1 @%0d  exp=%0d  got=%0d", sample_idx, t1, $signed(p1));
            end
            if (t2 !== $signed(p2)) begin
                errors = errors + 1;
                $display("#ERR p2 @%0d  exp=%0d  got=%0d", sample_idx, t2, $signed(p2));
            end

            if (errors > MAX_ERRORS) begin
                $display("[TB] Troppi errori (%0d). Stop.", errors);
                $fclose(f_out); $fclose(f_tgt);
                $finish;
            end
        end
    end

    // ========================================================================
    //  SEQUENZA PRINCIPALE
    // ========================================================================
    integer f;

    initial begin
        $dumpfile(VCD_FILE);
        $dumpvars(10, syntzulu_tb_mnist_snn_lp);

        f_tgt = $fopen(TARGET_FILE, "r");
        f_out = $fopen(OUTPUT_FILE, "w");

        // 0) Carico gli stream di spike dai file
        load_spike_files();

        // 1) Reset
        rst = 1'b1;
        repeat (RESET_CYCLES_HIGH) @(posedge clk);
        rst = 1'b0;
        repeat (RESET_CYCLES_LOW)  @(posedge clk);

        // 2) Carico i 4 banchi pesi
        load_weight_mem(1, W1_OFFSET);
        load_weight_mem(2, W2_OFFSET);
        load_weight_mem(3, W3_OFFSET);
        load_weight_mem(4, W4_OFFSET);
        repeat (POST_WEIGHTS_CYCLES) @(posedge clk);
        $display("[TB] Pesi caricati. Decay/threshold autoinizializzate via BRAM init.");

        // 3) Streammo NUM_FRAMES frame, sincronizzandomi sul valid top-level
        for (f = 0; f < NUM_FRAMES; f = f + 1) begin
            $display("[TB] Frame %0d/%0d -> bit %0d..%0d",
                     f+1, NUM_FRAMES,
                     f*BITS_PER_FRAME, (f+1)*BITS_PER_FRAME - 1);
            feed_frame(f * BITS_PER_FRAME);
            @(posedge valid);
            repeat (INTER_FRAME_CYCLES) @(posedge clk);
        end

        // 4) Drenaggio finale
        repeat (DRAIN_FINAL_CYCLES) @(posedge clk);

        $display("");
        $display("============================================================");
        if (errors == 0)
            $display("   *** TESTBENCH PASSATO CON SUCCESSO ***");
        else
            $display("   !!! TESTBENCH FALLITO !!!");
        $display("------------------------------------------------------------");
        $display("   valid_snn osservati : %0d", sample_idx);
        $display("   errori              : %0d", errors);
        $display("============================================================");
        $display("");
        $fclose(f_out);
        $fclose(f_tgt);
        $finish;
    end

    // ========================================================================
    //  Utility: log2 ceiling
    // ========================================================================
    function integer clogb2;
        input integer depth;
        for (clogb2 = 0; depth > 0; clogb2 = clogb2 + 1)
            depth = depth >> 1;
    endfunction

endmodule

// Reti implicite usate dai sorgenti RTL successivi sulla command line.
`default_nettype wire
