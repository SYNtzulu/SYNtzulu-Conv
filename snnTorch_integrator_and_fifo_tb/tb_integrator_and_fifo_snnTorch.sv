`timescale 1ns / 1ps

// Testbench for integrator_and_fifo_snnTorch
//
// Drives a sequence of `stimolo` values through the wrapper, exercising:
//   - reset / clear_counter
//   - single-input-feature mode (first_input_feature=last_input_feature=1)
//   - en pulses to clock samples through buffer_current_mem -> integrator -> fifo
//
// Outputs are dumped to wave.vcd. Stimuli can be loaded from
// `verilog_tb_files/stimolo.txt` (one signed hex value per line, WIDTH bits);
// if the file is missing a small inline pattern is used instead.


// OCCHIO CHE PER TESTARLO IL DECAY E LA THRESHOLD ERANO HARDCODED A UN VALORE COSTANTE

module tb_integrator_and_fifo_snnTorch;

    // ---- DUT parameters ------------------------------------------------
    localparam DEPTH             = 512;
    localparam WIDTH             = 16;
    localparam MAX_INPUT_FEATURE = 16;
    localparam DECAY_THR_FILE    = "";

    localparam CLK_PERIOD = 10; // 100 MHz

    // ---- DUT IO --------------------------------------------------------
    reg                  clk;
    reg                  rst;
    reg                  en;
    reg                  detection;
    reg                  reset_potential;
    reg                  fix_cnt;
    reg  [7:0]           square_dim_output_feature;
    reg                  conv_enable;
    reg                  dense_enable;
    reg                  pooling_spike_enable;
    reg                  first_input_feature;
    reg  [13:0]          decay;
    reg  signed [WIDTH-1:0] stimolo;
    reg  signed [WIDTH-1:0] threshold;
    reg                  last_input_feature;
    reg                  clear_counter;
    reg                  layer_integrated;
    reg                  recurrency_next;
    reg                  recurrency;
    reg                  output_feature_integrated;

    wire                 valid;
    wire                 spike;
    // The wrapper drives output_new as an unsigned 8-bit port, but the
    // value is logically signed (-128..127). Capture it raw and
    // sign-extend to WIDTH bits so it matches the 16-bit signed values
    // stored in neuron_states.txt.
    wire        [7:0]       output_new_raw;
    wire signed [WIDTH-1:0] output_new =
        {{(WIDTH-8){output_new_raw[7]}}, output_new_raw};

    // ---- DUT instance --------------------------------------------------
    integrator_and_fifo_snnTorch #(
        .DEPTH(DEPTH),
        .WIDTH(WIDTH),
        .MAX_INPUT_FEATURE(MAX_INPUT_FEATURE),
        .DECAY_THR_FILE(DECAY_THR_FILE)
    ) dut (
        .clk                       (clk),
        .rst                       (rst),
        .en                        (en),
        .detection                 (detection),
        .reset_potential           (reset_potential),
        .fix_cnt                   (fix_cnt),
        .square_dim_output_feature (64),
        .conv_enable               (conv_enable),
        .dense_enable              (dense_enable),
        .pooling_spike_enable      (pooling_spike_enable),
        .first_input_feature       (first_input_feature),
        .decay                     (decay),
        .stimolo                   (stimolo),
        .threshold                 (threshold),
        .last_input_feature        (last_input_feature),
        .valid                     (valid),
        .spike                     (spike),
        .output_new                (output_new_raw),
        .clear_counter             (clear_counter),
        .layer_integrated          (layer_integrated),
        .recurrency_next           (recurrency_next),
        .recurrency                (recurrency),
        .output_feature_integrated (output_feature_integrated),
        .M(6)
    );

    // ---- Clock ---------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- Image / processing geometry -----------------------------------
    // 8x8x2 input -> 8x8x8 output convolution.
    // Per output feature the controller streams N_IN_FEAT * SPATIAL stimoli:
    //   - first batch of 64: first_input_feature=1, last_input_feature=0
    //   - last  batch of 64: first_input_feature=0, last_input_feature=1
    // buffer_current_mem accumulates `mem[adr] += stimolo` only when
    // first_input_feature=0; the very first feature initializes mem[].
    localparam SQUARE_DIM   = 8;
    localparam SPATIAL      = SQUARE_DIM * SQUARE_DIM; // 64
    localparam N_IN_FEAT    = 4;
    localparam MAX_OUT_FEAT = 8;
    localparam N_TIMESTEP   = 10;
    // Stimulus buffer sized for the worst case:
    //   N_TIMESTEP * MAX_OUT_FEAT * N_IN_FEAT * SPATIAL
    // The actual number of timesteps / output features is derived from
    // how many values current_partials.txt actually contains.
    localparam MAX_STIMULI  = N_TIMESTEP * MAX_OUT_FEAT * N_IN_FEAT * SPATIAL;

    reg signed [WIDTH-1:0] stim_buf [0:MAX_STIMULI-1];
    integer total_stim;
    integer stim_per_ts;
    integer n_out_feat;

    // ---- Self-checking against golden files ---------------------------
    // For every cycle in which the LIF asserts `valid`, output_new is
    // compared against expected_output.txt and spike against
    // expected_spikes.txt. One value per line, hex.
    localparam MAX_VALID = N_TIMESTEP * MAX_OUT_FEAT * SPATIAL;
    reg signed [WIDTH-1:0] exp_out_buf   [0:MAX_VALID-1];
    reg                    exp_spike_buf [0:MAX_VALID-1];
    integer exp_out_count;
    integer exp_spike_count;
    integer valid_idx;
    integer n_errors_out;
    integer n_errors_spike;
    integer file_exp_out;
    integer file_exp_spike;
    integer r_exp;
    reg signed [WIDTH-1:0] tmp_exp_out;
    reg                    tmp_exp_spike;
    reg                    check_enable;

    // Shadow wires that always expose the expected value at the
    // current valid_idx, so they can be compared side-by-side with
    // output_new / spike in gtkwave.
    wire signed [WIDTH-1:0] exp_out_now =
        (valid_idx < exp_out_count)   ? exp_out_buf[valid_idx]   : '0;
    wire                    exp_spike_now =
        (valid_idx < exp_spike_count) ? exp_spike_buf[valid_idx] : 1'b0;
    // Live "is the current sample correct?" flags (only meaningful
    // when valid is high).
    wire out_match   = (output_new === exp_out_now);
    wire spike_match = (spike      === exp_spike_now);

    // ---- Stimuli helpers ----------------------------------------------
    integer file_in;
    integer r_in;
    integer cycle;
    integer i, j, k, t;
    integer base_idx;
    reg signed [WIDTH-1:0] tmp_stim;

    // Drive SPATIAL stimoli for one input-feature pass. The address counter
    // inside buffer_current_mem is forced back to 0 at the start of every
    // input feature so the same `mem[0..SPATIAL-1]` cells are reused, which
    // is what enables real accumulation across input features.
    task automatic drive_input_feature(input integer base,
                                       input bit    is_first,
                                       input bit    is_last);
        integer p;
        begin
            // Reset adr so the SPATIAL writes land on mem[0..SPATIAL-1].
            @(negedge clk);
            //force dut.buffer_current_mem_i.adr = 8'd0;
            first_input_feature = is_first;
            last_input_feature  = is_last;
            en                  = 1'b0;
            @(posedge clk);
            release dut.buffer_current_mem_i.adr;

            for (p = 0; p < SPATIAL; p = p + 1) begin
                @(negedge clk);
                en      = 1'b1;
                stimolo = stim_buf[base + p];
                @(posedge clk);
                #1;
                cycle = cycle + 1;
                $display("[%0t] cyc=%0d  first=%0b last=%0b  pos=%0d/%0d  stim=%0d  valid=%0b spike=%0b out=%0d",
                         $time, cycle, is_first, is_last, p, SPATIAL,
                         stim_buf[base + p], valid, spike, output_new);
            end

            @(negedge clk);
            en                  = 1'b0;
            first_input_feature = 1'b0;
            last_input_feature  = 1'b0;
        end
    endtask

    // Pulse output_feature_integrated for one cycle to advance dec_thr_mem
    // to the next (decay,threshold) pair for the next output feature.
    task automatic pulse_output_feature_integrated;
        begin
            @(negedge clk);
            output_feature_integrated = 1'b1;
            @(posedge clk);
            @(negedge clk);
            output_feature_integrated = 1'b0;
        end
    endtask

    // Pulse clear_counter at the boundary between timesteps. This rolls
    // back dec_thr_mem.rd_cnt and bram_fifo.rd_cnt/wr_cnt to 0 so the
    // next timestep restarts at the first output feature; the BRAM
    // contents (membrane potentials, decay/threshold table) survive.
    task automatic pulse_clear_counter;
        begin
            @(negedge clk);
            clear_counter = 1'b1;
            @(posedge clk);
            @(negedge clk);
            clear_counter = 1'b0;
        end
    endtask

    // Self-check: every posedge in which the LIF emits `valid` we compare
    // the current output_new and spike against the i-th value of the
    // golden files. The small #1 delay lets the combinational outputs
    // (output_new, spike) settle after the registered signals update.
    always @(posedge clk) begin
        #1;
        if (!rst && check_enable && valid) begin
            if (valid_idx < exp_out_count) begin
                if (output_new !== exp_out_buf[valid_idx]) begin
                    $display("[CHECK] OUT  MISMATCH idx=%0d t=%0t  got=%0d  exp=%0d",
                             valid_idx, $time, output_new, exp_out_buf[valid_idx]);
                    n_errors_out = n_errors_out + 1;
                end
            end
            if (valid_idx < exp_spike_count) begin
                if (spike !== exp_spike_buf[valid_idx]) begin
                    $display("[CHECK] SPIKE MISMATCH idx=%0d t=%0t  got=%0b  exp=%0b",
                             valid_idx, $time, spike, exp_spike_buf[valid_idx]);
                    n_errors_spike = n_errors_spike + 1;
                end
            end
            valid_idx = valid_idx + 1;
        end
    end

    // ---- Main ----------------------------------------------------------
    // Number of cells of buffer_current_mem.mem to expose in the VCD.
    // Must be <= the ROW parameter of buffer_current_mem (default 256).
    // Set to SPATIAL so the 64 cells used by the 8x8 output are visible.
    localparam BCM_ROW = SPATIAL;
    integer dump_i;

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_integrator_and_fifo_snnTorch);
        // Iverilog's $dumpvars does not expand reg arrays automatically:
        // enumerate every cell so gtkwave shows them as individual
        // signals under dut.buffer_current_mem_i.mem[*].
        for (dump_i = 0; dump_i < BCM_ROW; dump_i = dump_i + 1) begin
            $dumpvars(0, dut.buffer_current_mem_i.mem[dump_i]);
        end

        // The wrapper leaves the internal `M` (gain) wire unconnected.
        // Force it to a known value so the integrator path is not X.
        //force dut.lif_snnTorch_i.M = 8'sd5;

        // Defaults
        rst                       = 1'b1;
        en                        = 1'b0;
        detection                 = 1'b1;
        reset_potential           = 1'b0;
        fix_cnt                   = 1'b0;
        square_dim_output_feature = SQUARE_DIM[7:0];
        conv_enable               = 1'b1;
        dense_enable              = 1'b0;
        pooling_spike_enable      = 1'b0;
        first_input_feature       = 1'b0;
        last_input_feature        = 1'b0;
        decay                     = 14'd230;
        stimolo                   = '0;
        threshold                 = 25'sd780;
        clear_counter             = 1'b1;
        layer_integrated          = 1'b0;
        recurrency_next           = 1'b0;
        recurrency                = 1'b0;
        output_feature_integrated = 1'b0;
        cycle                     = 0;
        total_stim                = 0;
        exp_out_count             = 0;
        exp_spike_count           = 0;
        valid_idx                 = 0;
        n_errors_out              = 0;
        n_errors_spike            = 0;
        check_enable              = 1'b0;

        // Reset
        repeat (4) @(posedge clk);
        rst           = 1'b0;
        clear_counter = 1'b0;
        @(posedge clk);

        // Load all stimoli from file. Expected format: one signed hex
        // value per line (WIDTH-bit, two's complement). The file should
        // contain N_OUT_FEAT * N_IN_FEAT * SPATIAL = 1024 values for the
        // full 8x8x2 -> 8x8x8 case, but any multiple of SPATIAL*N_IN_FEAT
        // is accepted (one full output feature per multiple).
        file_in = $fopen("/home/luca/syntzulu_conv/snnTorch_integrator_and_fifo_tb/current_partials.txt", "r");
        if (file_in == 0) begin
            $display("current_partials.txt not found, generating ramp pattern");
            for (i = 0; i < N_IN_FEAT * SPATIAL; i = i + 1) begin
                stim_buf[i] = i[WIDTH-1:0];
                total_stim  = total_stim + 1;
            end
        end else begin
            while (!$feof(file_in) && total_stim < MAX_STIMULI) begin
                r_in = $fscanf(file_in, "%h\n", tmp_stim);
                if (r_in == 1) begin
                    stim_buf[total_stim] = tmp_stim;
                    total_stim           = total_stim + 1;
                end
            end
            $fclose(file_in);
        end

        // The file is expected to contain N_TIMESTEP timesteps back to
        // back (canonical ordering: timestep -> out_feat -> in_feat ->
        // spatial). Derive how many output features each timestep has
        // from the total count.
        stim_per_ts = total_stim / N_TIMESTEP;
        n_out_feat  = stim_per_ts / (N_IN_FEAT * SPATIAL);
        $display("Loaded %0d stimoli -> %0d timestep(s) x %0d output feature(s)",
                 total_stim, N_TIMESTEP, n_out_feat);

        // Load expected output_new values
        file_exp_out = $fopen("/home/luca/syntzulu_conv/snnTorch_integrator_and_fifo_tb/neuron_states.txt", "r");
        if (file_exp_out == 0) begin
            $display("WARNING: expected_output.txt not found, output_new check disabled");
        end else begin
            while (!$feof(file_exp_out) && exp_out_count < MAX_VALID) begin
                r_exp = $fscanf(file_exp_out, "%h\n", tmp_exp_out);
                if (r_exp == 1) begin
                    exp_out_buf[exp_out_count] = tmp_exp_out;
                    exp_out_count              = exp_out_count + 1;
                end
            end
            $fclose(file_exp_out);
            $display("Loaded %0d expected output_new values", exp_out_count);
        end

        // Load expected spike values
        file_exp_spike = $fopen("/home/luca/syntzulu_conv/snnTorch_integrator_and_fifo_tb/neuron_spikes.txt", "r");
        if (file_exp_spike == 0) begin
            $display("WARNING: expected_spikes.txt not found, spike check disabled");
        end else begin
            while (!$feof(file_exp_spike) && exp_spike_count < MAX_VALID) begin
                r_exp = $fscanf(file_exp_spike, "%h\n", tmp_exp_spike);
                if (r_exp == 1) begin
                    exp_spike_buf[exp_spike_count] = tmp_exp_spike;
                    exp_spike_count                = exp_spike_count + 1;
                end
            end
            $fclose(file_exp_spike);
            $display("Loaded %0d expected spike values", exp_spike_count);
        end

        // Enable on-the-fly checking from now on
        check_enable = 1'b1;
        if (n_out_feat == 0) begin
            $display("ERROR: not enough stimoli per timestep (need at least %0d, got %0d)",
                     N_IN_FEAT * SPATIAL, stim_per_ts);
            $finish;
        end
        if (stim_per_ts * N_TIMESTEP != total_stim) begin
            $display("WARNING: total stimoli (%0d) is not a multiple of N_TIMESTEP (%0d); trailing values ignored",
                     total_stim, N_TIMESTEP);
        end

        // Outer loop: SNN timesteps. Inside each timestep, run the full
        // output_feature x input_feature x spatial sweep. Between
        // timesteps pulse clear_counter so dec_thr_mem and the FIFO
        // counters restart at 0 (the membrane potentials stored in the
        // FIFO BRAM persist and act as `output_old` next timestep).
        for (t = 0; t < N_TIMESTEP; t = t + 1) begin
            $display("######## Timestep %0d/%0d ########", t, N_TIMESTEP);
            for (i = 0; i < n_out_feat; i = i + 1) begin
                $display("==== Output feature %0d/%0d ====", i, n_out_feat);
                for (j = 0; j < N_IN_FEAT; j = j + 1) begin
                    base_idx = t * stim_per_ts
                             + (i * N_IN_FEAT + j) * SPATIAL;
                    drive_input_feature(base_idx,
                                        j == 0,            // first_input_feature
                                        j == N_IN_FEAT-1); // last_input_feature
                end
                pulse_output_feature_integrated;
            end
            if (t < N_TIMESTEP - 1) pulse_clear_counter;
        end

        // Drain pipeline
        repeat (8) @(posedge clk);

        // Stop self-checking before $finish so any X transitions during
        // the drain phase don't cause spurious mismatches.
        check_enable = 1'b0;

        $display("============================================================");
        $display("Simulation completed: %0d cycles, %0d timestep(s) x %0d output feature(s)",
                 cycle, N_TIMESTEP, n_out_feat);
        $display("Self-check valid samples processed: %0d", valid_idx);
        if (exp_out_count > 0)
            $display("  output_new: %0d errors out of %0d checks",
                     n_errors_out,
                     (valid_idx < exp_out_count) ? valid_idx : exp_out_count);
        if (exp_spike_count > 0)
            $display("  spike     : %0d errors out of %0d checks",
                     n_errors_spike,
                     (valid_idx < exp_spike_count) ? valid_idx : exp_spike_count);
        if (n_errors_out == 0 && n_errors_spike == 0 &&
            (exp_out_count > 0 || exp_spike_count > 0))
            $display("ALL CHECKS PASSED");
        $display("============================================================");
        $finish;
    end

    // Safety timeout
    initial begin
        #(CLK_PERIOD * 100000);
        $display("TIMEOUT");
        $finish;
    end

endmodule
