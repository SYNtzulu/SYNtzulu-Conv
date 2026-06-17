`timescale 1ns / 1ps
`default_nettype none

`include "rtl/define.v"
`include `CONFIG_PATH

// ============================================================================
//  syntzulu_tb_mnist
//  ----------------------------------------------------------------------------
//  Testbench stand-alone equivalente a servant_tb_mnist (SoC-level), ma che
//  istanzia SOLO il blocco Syntzulu. Riproduce a mano tutto ciò che nel SoC
//  fa il firmware tramite SPI/CPU:
//     1) carica i 4 banchi di pesi nelle weight memory (pattern servant_spi)
//     2) inizializza le memorie di decay/threshold (auto via $readmemh nelle
//        BRAM init: i path sono cablati in snn_lp.sv come
//        "mnist/decay_thr_1.txt" / "mnist/decay_thr_2.txt", quindi la
//        simulazione DEVE essere lanciata dalla root del progetto)
//     3) alimenta `data_in` con gli stessi sample del SoC, presi dalla coda
//        di flash.txt
//     4) verifica online le correnti p1/p2 (output_new degli integratori L1/L2)
//        contro sim/target/mnist/snn_inference.txt (lo stesso file usato
//        dalla TB del SoC)
//
//  Convenzioni di confronto identiche a servant_tb_mnist.v:
//     • per ogni `valid_snn` (= valid_fifo dell'integratore L1) si scrive
//       una coppia (p1,p2) sul file di output e si confrontano due interi
//       consecutivi del file di target.
// ============================================================================

module syntzulu_tb_mnist;

    // ========================================================================
    //  PARAMETRI DI CONFIGURAZIONE — modificare qui
    // ========================================================================

    // ---- Path dei file (relativi alla root del progetto) -------------------
    localparam FLASH_FILE   = "sim/mem/mnist/flash.txt";                            // pesi + sample (formato $readmemh)
    localparam INSTR_FILE   = "flash/src/mnist/instruction.hex";                    // istruzioni (caricate via $readmemh in instruction_memory)
    localparam TARGET_FILE  = "sim/target/mnist/snn_inference.txt";                 // riferimento da confrontare
    localparam OUTPUT_FILE  = "sim/results/mnist/syntzulu_tb_mnist_inference.txt";  // dump correnti HW
    localparam LABEL_FILE   = "sim/results/mnist/syntzulu_tb_mnist_label.txt";      // dump label dal output_buffer
    localparam VCD_FILE     = "sim/results/mnist/syntzulu_tb_mnist.vcd";            // waveform

    // ---- Parametri di Syntzulu (specchio servant_syntzulu MNIST) ----------
    localparam ENCODING_BYPASS  = 0;
    localparam CHANNELS         = `INPUT_CHANNELS; // 32  (numero di word da 16 bit per frame)
    localparam DW               = `DW;             // 16  (data width della pipeline)
    localparam WIDTH            = 16;              // width interna della SNN
    localparam BUFFER_WIDTH     = `BUFFER_WIDTH;
    localparam N_CLASSES        = 10;
    localparam TIME_STEPS       = `TIME_STEPS;     // 10  (frame per inferenza)
    localparam MAX_NEURONS      = 128;
    localparam MAX_SYNAPSES     = 256;
    localparam LAYERS           = 8;
    localparam MAX_DECAY        = 4096;
    localparam MAX_THRESHOLD    = 65536;
    localparam INSTR_WIDTH      = 80;
    localparam WEIGHT_DEPTH_12  = 8192;            // depth in byte di ciascun banco pesi
    localparam WEIGHT_DEPTH_34  = 8192;

    // ---- Layout della flash --------------------------------------------------
    //   [0          .. 1*WEIGHT_DEPTH_12 - 1] -> WEIGHT_MEM_L1   (8192 byte)
    //   [1*WEIGHT_DEPTH_12 .. 2*WEIGHT_DEPTH_12 - 1] -> WEIGHT_MEM_L2
    //   [2*WEIGHT_DEPTH_12 .. 3*WEIGHT_DEPTH_12 - 1] -> WEIGHT_MEM_L3
    //   [3*WEIGHT_DEPTH_12 .. 4*WEIGHT_DEPTH_12 - 1] -> WEIGHT_MEM_L4
    //   [4*WEIGHT_DEPTH_12 .. ...]                   -> SAMPLE   (TIME_STEPS frame)
    localparam W1_OFFSET        = 0;
    localparam W2_OFFSET        = W1_OFFSET + WEIGHT_DEPTH_12;
    localparam W3_OFFSET        = W2_OFFSET + WEIGHT_DEPTH_12;
    localparam W4_OFFSET        = W3_OFFSET + WEIGHT_DEPTH_12;

    // Ogni banco è composto da WEIGHT_DEPTH_12/2 = 4096 word da 16 bit
    // (perché WEIGHT_DEPTH_12 conta i BYTE di flash, e una word=2 byte).
    localparam WORDS_PER_BANK   = WEIGHT_DEPTH_12 / 2;            // 4096

    // Sample region: TIME_STEPS frame, ciascuno da CHANNELS word da 16 bit.
    localparam SAMPLE_OFFSET    = 4 * WEIGHT_DEPTH_12;            // 32768
    localparam BYTES_PER_FRAME  = 2 * CHANNELS;                   // 64
    localparam NUM_FRAMES       = TIME_STEPS;                     // 10
    localparam SAMPLE_BYTES     = NUM_FRAMES * BYTES_PER_FRAME;   // 640
    localparam FLASH_BYTES      = SAMPLE_OFFSET + SAMPLE_BYTES;   // 33408

    // ---- Tuning del testbench ----------------------------------------------
    localparam MAX_ERRORS         = 100000; // alto: voglio vedere tutto il flow
    localparam RESET_CYCLES_HIGH  = 10;     // cicli di reset asserito
    localparam RESET_CYCLES_LOW   = 5;      // cicli dopo deassert prima di operare
    localparam POST_WEIGHTS_CYCLES= 50;     // settling dopo il caricamento pesi
    localparam INTER_FRAME_CYCLES = 20000;  // margine fra un frame e il successivo
                                            //   serve a drenare la pipeline a 2 layer:
                                            //   `valid` pulsa al primo end-of-inference
                                            //   ma per TIME_STEPS interno la SNN deve
                                            //   completare ulteriori giri prima che lo
                                            //   stato sia pulito per il frame successivo.
    localparam DRAIN_FINAL_CYCLES = 50000;  // drenaggio finale prima di chiudere

    // ========================================================================
    //  CLOCK & RESET
    // ========================================================================
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;   // 100 MHz, condiviso clk_enc/clk_snn

    // ========================================================================
    //  STIMOLI
    // ========================================================================
    // Ingressi dati / encoder
    reg                                   en      = 1'b0;
    reg signed [15:0]                     data_in = 16'd0;
    reg                                   detect  = 1'b0;

    // Porte di scrittura della WEIGHT_MEM_L1
    reg                                   w1_wren = 1'b0, w1_ena = 1'b0;
    reg [clogb2(WEIGHT_DEPTH_12-1)-1:0]   w1_addr = '0;
    reg [15:0]                            w1_data = 16'd0;

    // Porte di scrittura della WEIGHT_MEM_L2
    reg                                   w2_wren = 1'b0, w2_ena = 1'b0;
    reg [clogb2(WEIGHT_DEPTH_12-1)-1:0]   w2_addr = '0;
    reg [15:0]                            w2_data = 16'd0;

    // Porte di scrittura della WEIGHT_MEM_L3
    reg                                   w3_wren = 1'b0, w3_ena = 1'b0;
    reg [clogb2(WEIGHT_DEPTH_34-1)-1:0]   w3_addr = '0;
    reg [15:0]                            w3_data = 16'd0;

    // Porte di scrittura della WEIGHT_MEM_L4
    reg                                   w4_wren = 1'b0, w4_ena = 1'b0;
    reg [clogb2(WEIGHT_DEPTH_34-1)-1:0]   w4_addr = '0;
    reg [15:0]                            w4_data = 16'd0;

    // Uscite top di Syntzulu
    wire                                  valid;             // end-of-inference dell'ultimo layer
    wire                                  valid_class;       // = output_buffer_wr_en (decoding pronta)
    wire                                  integrated_neuron;

    // ========================================================================
    //  DUT
    //    Le memorie di decay/threshold di L1/L2 vengono inizializzate via
    //    $readmemh dentro `dec_thr_mem` (path cablato in snn_lp.sv:
    //    "mnist/decay_thr_1.txt" e "mnist/decay_thr_2.txt"). NON serve fare
    //    nulla qui, basta che la sim giri dalla root del progetto.
    // ========================================================================
    Syntzulu #(
        .ENCODING_BYPASS (ENCODING_BYPASS),
        .CHANNELS        (CHANNELS),
        .DW              (DW),
        .WIDTH           (WIDTH),
        .N_CLASSES       (N_CLASSES),
        .TIME_STEPS      (TIME_STEPS),
        .MAX_NEURONS     (MAX_NEURONS),
        .MAX_SYNAPSES    (MAX_SYNAPSES),
        .LAYERS          (LAYERS),
        .MAX_DECAY       (MAX_DECAY),
        .MAX_THRESHOLD   (MAX_THRESHOLD),
        .INSTR_WIDTH     (INSTR_WIDTH),
        .INSTR_FILE      (INSTR_FILE),
        .WEIGHTS_FILE_1  (""),    // weight mem caricate a runtime via porte (vedi sotto)
        .WEIGHTS_FILE_2  (""),
        .WEIGHTS_FILE_3  (""),
        .WEIGHTS_FILE_4  (""),
        .WEIGHT_DEPTH_12 (WEIGHT_DEPTH_12),
        .WEIGHT_DEPTH_34 (WEIGHT_DEPTH_34),
        .BUFFER_WIDTH    (BUFFER_WIDTH)
    ) dut (
        .clk_enc          (clk),
        .clk_snn          (clk),
        .rst              (rst),
        .en               (en),
        .data_in          (data_in),
        .detect           (detect),
        .encoding_bypass  (1'b0),

        .valid            (valid),
        .valid_class      (valid_class),
        .integrated_neuron(integrated_neuron),

        // weight memory L1
        .weight_mem_L1_wren    (w1_wren),
        .weight_mem_L1_wr_addr (w1_addr),
        .weight_mem_L1_data_in (w1_data),
        .weight_mem_L1_data_out(),
        .weight_mem_L1_ena     (w1_ena),
        // weight memory L2
        .weight_mem_L2_wren    (w2_wren),
        .weight_mem_L2_wr_addr (w2_addr),
        .weight_mem_L2_data_in (w2_data),
        .weight_mem_L2_data_out(),
        .weight_mem_L2_ena     (w2_ena),
        // weight memory L3
        .weight_mem_L3_wren    (w3_wren),
        .weight_mem_L3_wr_addr (w3_addr),
        .weight_mem_L3_data_in (w3_data),
        .weight_mem_L3_data_out(),
        .weight_mem_L3_ena     (w3_ena),
        // weight memory L4
        .weight_mem_L4_wren    (w4_wren),
        .weight_mem_L4_wr_addr (w4_addr),
        .weight_mem_L4_data_in (w4_data),
        .weight_mem_L4_data_out(),
        .weight_mem_L4_ena     (w4_ena),

        // output buffer non utilizzato qui (lettura via SPI nel SoC reale)
        .output_buffer_ren    (1'b0),
        .output_buffer_addr   (8'b0),
        .output_buffer_out    ()
    );

    // ========================================================================
    //  SONDE
    //    Stessa gerarchia usata dal TB del SoC (servant_tb_mnist.v) — così il
    //    confronto contro il file di target è 1:1.
    // ========================================================================
    wire signed [15:0]      p1          = dut.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.output_new;
    wire signed [15:0]      p2          = dut.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.output_new;
    wire                    valid_snn   = dut.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.valid_fifo;
    wire                    valid_label = dut.output_buffer_wr_en;
    wire [BUFFER_WIDTH-1:0] label       = dut.output_buffer_din;

    // === buffer_current di L1/L2 ===
    //   buffer_current     = uscita combinazionale di buffer_current_mem
    //   buffer_current_d   = versione registrata, è quella effettivamente
    //                        integrata dal LIF (input dell'integrator_i)
    //   valid_buffer_current(_d) = enable associato
    wire signed [15:0]      buf_curr_l1         = dut.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.buffer_current;
    wire signed [15:0]      buf_curr_l2         = dut.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.buffer_current;
    wire signed [15:0]      buf_curr_d_l1       = dut.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.buffer_current_d;
    wire signed [15:0]      buf_curr_d_l2       = dut.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.buffer_current_d;
    wire                    valid_buf_curr_l1   = dut.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.valid_buffer_current;
    wire                    valid_buf_curr_l2   = dut.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.valid_buffer_current;
    wire                    valid_buf_curr_d_l1 = dut.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.valid_buffer_current_d;
    wire                    valid_buf_curr_d_l2 = dut.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.valid_buffer_current_d;

    // Address pointer (write/read address) di buffer_current_mem
    wire [7:0] buf_mem_adr_l1 = dut.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.buffer_current_mem_i.adr;
    wire [7:0] buf_mem_adr_l2 = dut.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.buffer_current_mem_i.adr;

    // === Mirror dell'array `mem` di buffer_current_mem (256 × 16 bit) =======
    // Disabilitato: Icarus 10.3 non gestisce il generate-for con wire interno +
    // riferimento gerarchico mem[gi] e va in syntax error a cascata.
    // Se serve in gtkwave, abilitare la macro DUMP_BUF_MEM con un simulatore
    // più recente.
    localparam BUF_MEM_ROWS = 256;
`ifdef DUMP_BUF_MEM
    genvar gi;
    generate
        for (gi = 0; gi < BUF_MEM_ROWS; gi = gi + 1) begin : buf_mem_l1
            wire signed [15:0] cell;
            assign cell = dut.snn_lp_i.layer_lp_l1_i.neuron_lp_i.Voltage_i.buffer_current_mem_i.mem[gi];
        end
        for (gi = 0; gi < BUF_MEM_ROWS; gi = gi + 1) begin : buf_mem_l2
            wire signed [15:0] cell;
            assign cell = dut.snn_lp_i.layer_lp_l2_i.neuron_lp_i.Voltage_i.buffer_current_mem_i.mem[gi];
        end
    endgenerate
`endif

    // ========================================================================
    //  CARICAMENTO FLASH
    //    Si legge tutto il flash in un array di byte. Nel SoC la stessa
    //    sequenza viene ottenuta dallo spi_master_asic, qui si fa in un colpo
    //    via $readmemh.
    // ========================================================================
    reg [7:0] flash_mem [0:FLASH_BYTES-1];

    initial begin : load_flash
        integer i;
        for (i = 0; i < FLASH_BYTES; i = i + 1) flash_mem[i] = 8'h00;
        $readmemh(FLASH_FILE, flash_mem);
        $display("[TB] Flash %s caricato (%0d byte: %0d weights + %0d sample)",
                 FLASH_FILE, FLASH_BYTES, SAMPLE_OFFSET, SAMPLE_BYTES);
    end

    // ========================================================================
    //  TASK: load_weight_mem
    //  ------------------------------------------------------------------------
    //  Carica un singolo banco pesi a partire da `base_offset` (in byte) della
    //  flash. Replica esattamente il pattern di servant_spi.v:
    //
    //     • 8192 byte di flash per banco -> 4096 word da 16 bit
    //     • word[i] = { flash[base + 2i], flash[base + 2i + 1] }
    //         (primo byte in posizione HIGH, secondo in LOW)
    //     • si scrive a indirizzi crescenti, una word per ciclo di clock,
    //       tenendo wren/ena alti per tutta la durata.
    //
    //  `which` seleziona il banco (1=L1, 2=L2, 3=L3, 4=L4) ed evita di
    //  alzare i wren degli altri banchi.
    // ========================================================================
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
                // Compongo la word a 16 bit dai due byte consecutivi della flash
                word = {flash_mem[base_offset + 2*i],
                        flash_mem[base_offset + 2*i + 1]};

                @(posedge clk);
                // Solo il banco selezionato riceve la scrittura
                case (which)
                    1: begin w1_wren <= 1'b1; w1_ena <= 1'b1; w1_addr <= i[12:0]; w1_data <= word; end
                    2: begin w2_wren <= 1'b1; w2_ena <= 1'b1; w2_addr <= i[12:0]; w2_data <= word; end
                    3: begin w3_wren <= 1'b1; w3_ena <= 1'b1; w3_addr <= i[12:0]; w3_data <= word; end
                    4: begin w4_wren <= 1'b1; w4_ena <= 1'b1; w4_addr <= i[12:0]; w4_data <= word; end
                endcase
            end

            // Disasserto tutti i wren dopo l'ultimo write
            @(posedge clk);
            w1_wren <= 1'b0; w1_ena <= 1'b0;
            w2_wren <= 1'b0; w2_ena <= 1'b0;
            w3_wren <= 1'b0; w3_ena <= 1'b0;
            w4_wren <= 1'b0; w4_ena <= 1'b0;
        end
    endtask

    // ========================================================================
    //  TASK: feed_frame
    //  ------------------------------------------------------------------------
    //  Manda un frame (CHANNELS word da 16 bit) sull'ingresso `data_in` di
    //  Syntzulu, replicando ciò che il firmware del SoC fa con
    //  spi_load_sample(). Il dataflow lato HW è:
    //
    //     data_in --> encoding_spike_buffer (BRAM da CHANNELS×16 bit)
    //              --> stream s1/s2 (8 bit-pair per word)
    //              --> snn_lp -> layer_lp L1 -> layer_lp L2 -> decoding_slot
    //
    //  Layout in flash (uguale al payload SPI del SoC):
    //     byte[base + 2i]   = MSB della word i
    //     byte[base + 2i+1] = LSB della word i
    //
    //  Si tiene `en` alto per CHANNELS cicli (uno per word) e poi lo si
    //  abbassa: il buffer interno rileva pointer == CHANNELS-1 e parte in
    //  streaming verso la SNN. Da quel momento NON bisogna più scrivere
    //  finché non finisce lo streaming, altrimenti la BRAM viene corrotta.
    // ========================================================================
    task automatic feed_frame;
        input integer base_offset;
        integer i;
        reg [15:0] word;
        begin
            for (i = 0; i < CHANNELS; i = i + 1) begin
                word = {flash_mem[base_offset + 2*i],
                        flash_mem[base_offset + 2*i + 1]};
                @(posedge clk);
                en      <= 1'b1;
                data_in <= word;
            end

            // Spengo en al ciclo successivo all'ultima word
            @(posedge clk);
            en      <= 1'b0;
            data_in <= 16'd0;
        end
    endtask

    // ========================================================================
    //  CONFRONTO ONLINE vs TARGET
    //  ------------------------------------------------------------------------
    //  Per ogni `valid_snn` (ciclo in cui l'integratore di L1 produce un
    //  output) si:
    //      1) scrivono le due correnti correnti hardware p1/p2 sul file di
    //         output, e l'eventuale label sul label file
    //      2) si leggono due interi consecutivi dal file di target (prima
    //         atteso p1, poi atteso p2 — stesso ordine di servant_tb_mnist)
    //      3) si confronta e si stampa #ERR su mismatch
    //  Dopo MAX_ERRORS errori si interrompe la simulazione.
    // ========================================================================
    integer        f_out, f_tgt, f_lbl, dummy;
    integer signed t1, t2;
    integer        sample_idx = 0;
    integer        errors     = 0;

    always @(posedge clk) begin
        if (!rst && valid_snn) begin
            sample_idx <= sample_idx + 1;

            if (valid_label)
                $fwrite(f_lbl, "[%0d\n", label);

            $fwrite(f_out, "[%0d,%0d],\n", $signed(p1), $signed(p2));
            $display("#[VALID #%0d  HW: p1=%0d  p2=%0d  buf_d_L1=%0d  buf_d_L2=%0d]",
                     sample_idx, $signed(p1), $signed(p2),
                     $signed(buf_curr_d_l1), $signed(buf_curr_d_l2));

            // Lettura dei due target attesi (p1 atteso, poi p2 atteso)
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
                $fclose(f_out); $fclose(f_tgt); $fclose(f_lbl);
                $finish;
            end
        end
    end

    // ========================================================================
    //  SEQUENZA PRINCIPALE
    //
    //     reset --> carica i 4 banchi pesi --> per ogni frame:
    //         feed_frame(...) --> attesa fine inferenza --> margine
    //     --> drenaggio finale --> chiusura file --> $finish
    // ========================================================================
    integer f;

    initial begin
        $dumpfile(VCD_FILE);
        $dumpvars(0, syntzulu_tb_mnist);

        f_tgt = $fopen(TARGET_FILE, "r");
        f_out = $fopen(OUTPUT_FILE, "w");
        f_lbl = $fopen(LABEL_FILE,  "w");

        // ---- Reset --------------------------------------------------------
        rst = 1'b1;
        repeat (RESET_CYCLES_HIGH) @(posedge clk);
        rst = 1'b0;
        repeat (RESET_CYCLES_LOW)  @(posedge clk);

        // ---- 1) Carico i 4 banchi pesi -----------------------------------
        load_weight_mem(1, W1_OFFSET);
        load_weight_mem(2, W2_OFFSET);
        load_weight_mem(3, W3_OFFSET);
        load_weight_mem(4, W4_OFFSET);
        repeat (POST_WEIGHTS_CYCLES) @(posedge clk);
        $display("[TB] Pesi caricati. Decay/threshold autoinizializzate via BRAM init.");

        // ---- 3) Alimento i frame in ingresso -----------------------------
        //   Sincronizzazione fra frame:
        //     • aspetto il primo pulse di `valid` (= layer_integrated &&
        //       last_layer) che indica la fine dell'inferenza dell'ultimo
        //       layer per quel frame.
        //     • aggiungo INTER_FRAME_CYCLES per drenare la pipeline (FIFO
        //       integratore, spike_mem, decay/thr counters, decoding_slot)
        //       prima di iniziare il frame successivo.
        for (f = 0; f < NUM_FRAMES; f = f + 1) begin
            $display("[TB] Frame %0d/%0d -> data_in (flash byte %0d..%0d)",
                     f+1, NUM_FRAMES,
                     SAMPLE_OFFSET + f*BYTES_PER_FRAME,
                     SAMPLE_OFFSET + (f+1)*BYTES_PER_FRAME - 1);
            feed_frame(SAMPLE_OFFSET + f*BYTES_PER_FRAME);
            @(posedge valid);
            repeat (INTER_FRAME_CYCLES) @(posedge clk);
        end

        // ---- Drenaggio finale --------------------------------------------
        repeat (DRAIN_FINAL_CYCLES) @(posedge clk);

        $display("[TB] Fine inferenza. valid_snn osservati = %0d, errori = %0d",
                 sample_idx, errors);
        $fclose(f_out);
        $fclose(f_tgt);
        $fclose(f_lbl);
        $finish;
    end

    // ========================================================================
    //  TB-only SPIKE COUNTERS
    //  ------------------------------------------------------------------------
    //  Conta gli spike che entrano in snn_lp dall'encoder, senza toccare
    //  l'RTL. Probano segnali interni via hierarchical reference.
    // ========================================================================

    // Probes
    wire tb_valid_enc     = dut.encoding_slot_i.encoding_spike_buffer_i.valid_encoding;
    wire tb_s1_enc        = dut.encoding_slot_i.encoding_spike_buffer_i.s1_encoding;
    wire tb_s2_enc        = dut.encoding_slot_i.encoding_spike_buffer_i.s2_encoding;
    wire tb_valid_s1_mem  = dut.snn_lp_i.spike_mem.valid_s1;
    wire tb_valid_s2_mem  = dut.snn_lp_i.spike_mem.valid_s2;

    // Contatori
    integer tb_total_pair_cycles  = 0;
    integer tb_total_s1_high      = 0;
    integer tb_total_s2_high      = 0;
    integer tb_total_valid_s1_mem = 0;
    integer tb_total_valid_s2_mem = 0;
    integer tb_frame_pair_cycles  = 0;
    integer tb_frame_s1_high      = 0;
    integer tb_frame_s2_high      = 0;
    integer tb_frame_idx_cnt      = 0;

    always @(posedge clk) begin
        if (rst) begin
            tb_total_pair_cycles  <= 0;
            tb_total_s1_high      <= 0;
            tb_total_s2_high      <= 0;
            tb_total_valid_s1_mem <= 0;
            tb_total_valid_s2_mem <= 0;
            tb_frame_pair_cycles  <= 0;
            tb_frame_s1_high      <= 0;
            tb_frame_s2_high      <= 0;
        end else begin
            if (tb_valid_enc) begin
                tb_total_pair_cycles <= tb_total_pair_cycles + 1;
                tb_frame_pair_cycles <= tb_frame_pair_cycles + 1;
                if (tb_s1_enc) begin
                    tb_total_s1_high <= tb_total_s1_high + 1;
                    tb_frame_s1_high <= tb_frame_s1_high + 1;
                end
                if (tb_s2_enc) begin
                    tb_total_s2_high <= tb_total_s2_high + 1;
                    tb_frame_s2_high <= tb_frame_s2_high + 1;
                end
            end
            if (tb_valid_s1_mem) tb_total_valid_s1_mem <= tb_total_valid_s1_mem + 1;
            if (tb_valid_s2_mem) tb_total_valid_s2_mem <= tb_total_valid_s2_mem + 1;
        end
    end

    // Stampa il bilancio a fine inferenza di ogni frame (sul pulse di valid top-level)
    always @(posedge clk) begin
        if (!rst && valid) begin
            tb_frame_idx_cnt <= tb_frame_idx_cnt + 1;
            $display("[SPIKE-CNT frame %0d] pair_cycles=%0d  s1_high=%0d  s2_high=%0d  |  cum spike_mem valid_s1=%0d  valid_s2=%0d",
                     tb_frame_idx_cnt + 1,
                     tb_frame_pair_cycles, tb_frame_s1_high, tb_frame_s2_high,
                     tb_total_valid_s1_mem, tb_total_valid_s2_mem);
            tb_frame_pair_cycles <= 0;
            tb_frame_s1_high     <= 0;
            tb_frame_s2_high     <= 0;
        end
    end

    // ========================================================================
    //  Utility: log2 ceiling (uguale a quello usato dentro Syntzulu)
    // ========================================================================
    function integer clogb2;
        input integer depth;
        for (clogb2 = 0; depth > 0; clogb2 = clogb2 + 1)
            depth = depth >> 1;
    endfunction

endmodule

// I file RTL del progetto fanno uso di reti implicite (`valid_fifo`,
// `start_instruction`, `pooling_enable`, ...). Riporto `default_nettype`
// al valore di default (`wire`) prima che iverilog elabori i file RTL
// indicati dopo questo sulla command line.
`default_nettype wire
