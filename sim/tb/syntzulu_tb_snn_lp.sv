`timescale 1ns / 1ps
`default_nettype none

`include "rtl/define.v"
`include `CONFIG_PATH

// ============================================================================
//  syntzulu_tb_snn_lp
//  ----------------------------------------------------------------------------
//  Stand-alone testbench that instantiates ONLY the snn_lp module (no Syntzulu
//  top, no encoder). Dataset-independent: the data folder is
//  chosen by the `PATH macro in rtl/define.v.
//
//     • the s1_encoding / s2_encoding inputs are read directly from two
//       text files, one bit per row ($readmemb format):
//          `PATH/input_even.txt  -> s1_encoding
//          `PATH/input_odd.txt   -> s2_encoding
//     • input_buffer_valid is held high by the TB for the whole duration of the
//       frame streaming; the rising edge generates start_instruction in snn_lp.
//
//  The weights (32-bit) are loaded from `PATH/weights.txt and written at runtime via
//  ports: layer 1 from the weight_mem_L1 port, layer 2 from the weight_mem_L2 port.
//  The decay/threshold memories are self-initialized via $readmemh inside layer_lp from the
//  files `PATH/decay_thr_1.txt / _2.txt (DATA_DIR passed to snn_lp = `PATH).
//  The sim MUST be launched from the project root.
// ============================================================================

module syntzulu_tb_snn_lp;

    // ========================================================================
    //  CONFIGURATION PARAMETERS
    // ========================================================================

    // ---- File paths (relative to the project root) -------------------
    //  All data paths derive from `PATH (defined in rtl/define.v):
    //  just change that macro to point to another dataset folder.
    localparam WEIGHTS_FILE = {`PATH, "/weights.txt"};       // 32-bit weights (4 bytes/row, $readmemh)
    localparam S1_FILE      = {`PATH, "/input_even.txt"};    // s1_encoding bit (one per row)
    localparam S2_FILE      = {`PATH, "/input_odd.txt"};     // s2_encoding bit (one per row)
    localparam INSTR_FILE   = {`PATH, "/instruction.hex"};   // instructions (16-bit/row)
    localparam DECAY1_FILE  = {`PATH, "/decay_thr_1.txt"};   // decay/threshold layer 1 (32-bit/row)
    localparam DECAY2_FILE  = {`PATH, "/decay_thr_2.txt"};   // decay/threshold layer 2 (32-bit/row)
    localparam TARGET_FILE  = {`PATH, "/snn_inference.txt"}; // p1/p2 reference
    localparam OUTPUT_FILE  = {`PATH, "/inference_out.txt"}; // HW currents dump
    localparam VCD_FILE     = "syntzulu_tb_snn_lp.vcd";                 // waveform

    // ---- snn_lp parameters (mirror of the servant_syntzulu configuration) -
    localparam WIDTH            = 8;
    localparam TIME_STEPS       = `TIME_STEPS;     // 10
    localparam MAX_NEURONS      = 128;
    localparam MAX_SYNAPSES     = 256;
    localparam LAYERS           = 8;
    localparam INSTR_WIDTH      = 80;
    localparam WEIGHT_DEPTH_12  = 4096;
    localparam WEIGHT_DEPTH_34  = 4096;

    // ---- weights.txt layout (32-bit weights: 4 bytes per word) --------------
    //   8192 words = 4096 (layer 1, L1 port) + 4096 (layer 2, L3 port).
    //   A single 32-bit BRAM per layer (RAM_DEPTH 4096).
    localparam WORDS_PER_MEM    = WEIGHT_DEPTH_12    ;       // 4096 words per memory
    localparam L1_BYTE_OFFSET   = 0;                         // layer 1 -> L1 port
    localparam L2_BYTE_OFFSET   = 4 * WORDS_PER_MEM;         // layer 2 -> L3 port (16384)
    localparam WEIGHTS_BYTES    = 8 * WORDS_PER_MEM;         // 32768 total bytes

    // ---- instruction/decay mem layout (loaded at runtime via ports) ------
    localparam INSTR_DEPTH_TB   = LAYERS * INSTR_WIDTH / 16;  // 40 words of 16 bits
    localparam DECAY_DEPTH      = 1024;                       // = DEPTH_FIFO of snn_lp

    // ---- s1/s2 stream -----------------------------------------------------
    //   Input feature map: INPUT_H × INPUT_W × INPUT_C  (1 bit per spike).
    //   Streamed as pairs (s1,s2) per cycle
    //      ->  BITS_PER_FRAME = H*W*C / 2  pairs/frame.
    //   Current setup: 16 × 16 × 16  =  4096 spikes  ->  2048 pairs/frame.
    localparam INPUT_H          = 16;
    localparam INPUT_W          = 16;
    localparam INPUT_C          = 16;
    localparam BITS_PER_FRAME   = (INPUT_H * INPUT_W * INPUT_C) / 2;   // 2048
    localparam NUM_FRAMES       = TIME_STEPS;                          // 10
    localparam MAX_BITS         = BITS_PER_FRAME * NUM_FRAMES;

    // ---- Tuning -----------------------------------------------------------
    localparam MAX_ERRORS         = 0;
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

    // Weight memory write ports (one per layer, 32-bit)
    reg                                  w1_wren = 1'b0;  // layer 1 (L1 port)
    reg [clogb2(WEIGHT_DEPTH_12-1)-1:0]  w1_addr = '0;
    reg [31:0]                           w1_data = 32'd0;
    reg                                  w2_wren = 1'b0;  // layer 2 (L2 port)
    reg [clogb2(WEIGHT_DEPTH_34-1)-1:0]  w2_addr = '0;
    reg [31:0]                           w2_data = 32'd0;

    // Decay/threshold mem (32-bit) and instruction mem (16-bit) write ports
    reg                                  d1_wren = 1'b0;  // decay layer 1
    reg [clogb2(DECAY_DEPTH-1)-1:0]      d1_addr = '0;
    reg [31:0]                           d1_data = 32'd0;
    reg                                  d2_wren = 1'b0;  // decay layer 2
    reg [clogb2(DECAY_DEPTH-1)-1:0]      d2_addr = '0;
    reg [31:0]                           d2_data = 32'd0;
    reg                                  im_wren = 1'b0;                 // instruction mem
    reg [clogb2(INSTR_DEPTH_TB-1)-1:0]   im_addr = '0;
    reg [15:0]                           im_data = 16'd0;

    // snn_lp outputs
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
        .INSTR_WIDTH     (INSTR_WIDTH),
        .INSTR_FILE      (""),    // instr mem loaded at runtime via port
        .DATA_DIR        (`PATH),
        .DECAY_THR_FILE_1(""),    // decay mem L1 loaded at runtime via port
        .DECAY_THR_FILE_2(""),    // decay mem L2 loaded at runtime via port
        .WEIGHTS_FILE_1  (""),    // weight mem loaded at runtime via ports
        .WEIGHTS_FILE_3  (""),
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

        // weight memory L1 (layer 1)
        .weight_mem_L1_wren    (w1_wren),
        .weight_mem_L1_wr_addr (w1_addr),
        .weight_mem_L1_data_in (w1_data),
        // weight memory L2 (layer 2)
        .weight_mem_L2_wren    (w2_wren),
        .weight_mem_L2_wr_addr (w2_addr),
        .weight_mem_L2_data_in (w2_data),

        // decay/threshold memory (layer 1)
        .decay_mem_L1_wren     (d1_wren),
        .decay_mem_L1_wr_addr  (d1_addr),
        .decay_mem_L1_data_in  (d1_data),
        // decay/threshold memory (layer 2)
        .decay_mem_L2_wren     (d2_wren),
        .decay_mem_L2_wr_addr  (d2_addr),
        .decay_mem_L2_data_in  (d2_data),
        // instruction memory
        .instr_mem_wren        (im_wren),
        .instr_mem_wr_addr     (im_addr),
        .instr_mem_data_in     (im_data),

        .voltage_1              (voltage_1),
        .voltage_2              (voltage_2),
        .s1                     (s1_out),
        .s2                     (s2_out),
        .last_layer             (last_layer),
        .integrated_neurons_cnt (integrated_neurons_cnt),
        .input_buffer_valid     (input_buffer_valid)
    );

    // ========================================================================
    //  PROBES  (hierarchy without the .snn_lp_i. prefix of the full TB)
    // ========================================================================
    wire signed [15:0] p1        = dut.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.output_new;
    wire signed [15:0] p2        = dut.layer_lp_l2_i.neuron_lp_i.Voltage_i.integrator_i.output_new;
    wire               valid_snn = dut.layer_lp_l1_i.neuron_lp_i.Voltage_i.integrator_i.valid_fifo;

    wire signed [15:0] buf_curr_d_l1 = dut.layer_lp_l1_i.neuron_lp_i.Voltage_i.buffer_current_d;
    wire signed [15:0] buf_curr_d_l2 = dut.layer_lp_l2_i.neuron_lp_i.Voltage_i.buffer_current_d;

    // Probes on the spike-mem write valid (useful for debug)
    wire tb_valid_s1_mem = dut.spike_mem.valid_s1;
    wire tb_valid_s2_mem = dut.spike_mem.valid_s2;

    // ------------------------------------------------------------------------
    //  conv probes: the anded_weights are unpacked arrays internal to conv.sv,
    //  which $dumpvars does NOT dump automatically. I alias them here onto scalar
    //  wires so they appear in the VCD. conv has DATA_WIDTH = WEIGHT = 8 -> [7:0].
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
    //  LOAD WEIGHTS (same as the full TB)
    // ========================================================================
    reg [7:0] weights_mem [0:WEIGHTS_BYTES-1];

    initial begin : load_weights
        integer i;
        for (i = 0; i < WEIGHTS_BYTES; i = i + 1) weights_mem[i] = 8'h00;
        $readmemh(WEIGHTS_FILE, weights_mem);
        $display("[TB] 32-bit weights loaded from %s (%0d bytes)", WEIGHTS_FILE, WEIGHTS_BYTES);
    end

    // Writes a weight memory (32-bit, 4096 words) through the indicated port.
    //   port = 1 -> weight_mem_L1 port (layer 1)
    //   port = 2 -> weight_mem_L2 port (layer 2)
    //   base_byte = byte offset inside weights_mem.
    // Each word is packed big-endian: {b0,b1,b2,b3} -> 0xb0b1b2b3.
    task automatic load_weight_mem;
        input integer port;
        input integer base_byte;
        integer i;
        reg [31:0] word;
        begin
            $display("[TB] Loading WEIGHT_MEM via port L%0d (weights bytes %0d..%0d, %0d words)",
                     port, base_byte,
                     base_byte + 4*WORDS_PER_MEM - 1, WORDS_PER_MEM);

            for (i = 0; i < WORDS_PER_MEM; i = i + 1) begin
                word = {weights_mem[base_byte + 4*i],
                        weights_mem[base_byte + 4*i + 1],
                        weights_mem[base_byte + 4*i + 2],
                        weights_mem[base_byte + 4*i + 3]};
                @(posedge clk);
                case (port)
                    1: begin w1_wren <= 1'b1; w1_addr <= i[12:0]; w1_data <= word; end
                    2: begin w2_wren <= 1'b1; w2_addr <= i[12:0]; w2_data <= word; end
                endcase
            end

            @(posedge clk);
            w1_wren <= 1'b0;
            w2_wren <= 1'b0;
        end
    endtask

    // Loads the instruction mem (16-bit words) from instruction.hex, writing
    // at runtime via the instr_mem port. Must be called with rst high: the
    // internal FSM of the instruction_memory stays idle until rst is released.
    task automatic load_instr_mem;
        integer f, c, i;
        reg [15:0] word;
        begin
            f = $fopen(INSTR_FILE, "r");
            if (f == 0) begin
                $display("[TB] ERROR: cannot open %s", INSTR_FILE);
                $finish;
            end
            i = 0;
            while (!$feof(f) && i < INSTR_DEPTH_TB) begin
                c = $fscanf(f, "%h\n", word);
                if (c == 1) begin
                    @(posedge clk);
                    im_wren <= 1'b1; im_addr <= i[clogb2(INSTR_DEPTH_TB-1)-1:0]; im_data <= word;
                    i = i + 1;
                end
            end
            @(posedge clk);
            im_wren <= 1'b0;
            $fclose(f);
            $display("[TB] Instruction mem loaded (%0d words from %s)", i, INSTR_FILE);
        end
    endtask

    // Loads a decay/threshold mem (32-bit words) writing via port:
    //   port = 1 -> decay_thr_1.txt on the L1 port
    //   port = 2 -> decay_thr_2.txt on the L2 port
    task automatic load_decay_mem;
        input integer port;
        integer f, c, i;
        reg [31:0] word;
        begin
            f = (port == 1) ? $fopen(DECAY1_FILE, "r") : $fopen(DECAY2_FILE, "r");
            if (f == 0) begin
                $display("[TB] ERROR: cannot open decay file (port %0d)", port);
                $finish;
            end
            i = 0;
            while (!$feof(f) && i < DECAY_DEPTH) begin
                c = $fscanf(f, "%h\n", word);
                if (c == 1) begin
                    @(posedge clk);
                    case (port)
                        1: begin d1_wren <= 1'b1; d1_addr <= i[clogb2(DECAY_DEPTH-1)-1:0]; d1_data <= word; end
                        2: begin d2_wren <= 1'b1; d2_addr <= i[clogb2(DECAY_DEPTH-1)-1:0]; d2_data <= word; end
                    endcase
                    i = i + 1;
                end
            end
            @(posedge clk);
            d1_wren <= 1'b0;
            d2_wren <= 1'b0;
            $fclose(f);
            $display("[TB] Decay mem L%0d loaded (%0d words)", port, i);
        end
    endtask

    // ========================================================================
    //  LOADING s1 / s2 STREAM FROM FILES
    //  ------------------------------------------------------------------------
    //  Expected format: one bit ('0' or '1') per row, separated by whitespace.
    //  $fscanf("%b") tolerates spaces/newlines and ignores unrecognized tokens.
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
                $display("[TB] ERROR: cannot open %s", S1_FILE);
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
                $display("[TB] ERROR: cannot open %s", S2_FILE);
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
            $display("[TB] Read s1=%0d bits, s2=%0d bits  ->  using %0d bits (%0d frames of %0d bits)",
                     s1_count, s2_count, total_bits,
                     total_bits / BITS_PER_FRAME, BITS_PER_FRAME);

            if (total_bits < NUM_FRAMES * BITS_PER_FRAME)
                $display("[TB] WARNING: not enough bits for %0d frames (need %0d). Missing bits stay 0.",
                         NUM_FRAMES, NUM_FRAMES * BITS_PER_FRAME);
        end
    endtask

    // ========================================================================
    //  TASK: feed_frame
    //  ------------------------------------------------------------------------
    //  Streams BITS_PER_FRAME pairs (s1,s2) to snn_lp, replicating what
    //  encoding_spike_buffer does when its buffer fills up:
    //     • en (= valid_encoding on the encoder side) high for the whole duration
    //     • input_buffer_valid (= valid_encoding on the snn_lp side) likewise, so
    //       that the rising edge generates start_instruction.
    //  Between one frame and the next both return to 0, so that the new
    //  rise restarts start_instruction for the following frame.
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
    //  ONLINE COMPARISON vs TARGET (identical to the full TB)
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
                $display("[TB] Too many errors (%0d). Stop.", errors);
                $fclose(f_out); $fclose(f_tgt);
                $finish;
            end
        end
    end

    // ========================================================================
    //  MAIN SEQUENCE
    // ========================================================================
    integer f;

    initial begin
        $dumpfile(VCD_FILE);
        $dumpvars(10, syntzulu_tb_snn_lp);

        f_tgt = $fopen(TARGET_FILE, "r");
        f_out = $fopen(OUTPUT_FILE, "w");

        // 0) Load the spike streams from files
        load_spike_files();

        // 1) Reset. The instruction mem must be written WHILE rst is high: its
        //    internal FSM stays idle and does not latch wrong instructions.
        rst = 1'b1;
        repeat (RESET_CYCLES_HIGH) @(posedge clk);
        load_instr_mem();
        rst = 1'b0;
        repeat (RESET_CYCLES_LOW)  @(posedge clk);

        // 2) Load weights and decay/threshold via ports
        load_weight_mem(1, L1_BYTE_OFFSET);   // layer 1 -> L1 port
        load_weight_mem(2, L2_BYTE_OFFSET);   // layer 2 -> L2 port
        load_decay_mem(1);                    // decay/threshold layer 1
        load_decay_mem(2);                    // decay/threshold layer 2
        repeat (POST_WEIGHTS_CYCLES) @(posedge clk);
        $display("[TB] Weights and decay/threshold loaded via ports.");

        // 3) Stream NUM_FRAMES frames, synchronizing on the top-level valid
        for (f = 0; f < NUM_FRAMES; f = f + 1) begin
            $display("[TB] Frame %0d/%0d -> bit %0d..%0d",
                     f+1, NUM_FRAMES,
                     f*BITS_PER_FRAME, (f+1)*BITS_PER_FRAME - 1);
            feed_frame(f * BITS_PER_FRAME);
            @(posedge valid);
            repeat (INTER_FRAME_CYCLES) @(posedge clk);
        end

        // 4) Final drain
        repeat (DRAIN_FINAL_CYCLES) @(posedge clk);

        $display("");
        $display("============================================================");
        if (errors == 0)
            $display("   *** TESTBENCH PASSED SUCCESSFULLY ***");
        else
            $display("   !!! TESTBENCH FAILED !!!");
        $display("------------------------------------------------------------");
        $display("   valid_snn observed  : %0d", sample_idx);
        $display("   errors              : %0d", errors);
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

// Implicit nets used by the subsequent RTL sources on the command line.
`default_nettype wire
