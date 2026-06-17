`timescale 1ns / 1ps

`include "params.vh"

module tb_integrator;

    reg clk, rst;
    reg en, detection, conv_enable, pooling_spike_enable;
    reg last_input_feature, recurrency, recurrency_next;

    reg  [NBITS_VOLTAGE-1:0] output_old;
    reg  [NBITS_THR-1:0]     threshold;
    reg  [NBITS_DECAY-1:0]   decay;
    reg  [NBITS_M-1:0]       M;
    reg  signed [15:0]       buffer_current;

    wire valid, valid_fifo, spike;
    wire [NBITS_VOLTAGE-1:0] output_new;

    // DUT
    integrator_snnTorch #(
        .nbits_M       (NBITS_M),
        .nbits_thr     (NBITS_THR),
        .nbits_decay   (NBITS_DECAY),
        .nbits_voltage (NBITS_VOLTAGE)
    ) dut (
        .clk(clk), .rst(rst),
        .en(en), .detection(detection),
        .conv_enable(conv_enable),
        .pooling_spike_enable(pooling_spike_enable),
        .last_input_feature(last_input_feature),
        .recurrency(recurrency),
        .recurrency_next(recurrency_next),
        .output_old(output_old),
        .threshold(threshold),
        .decay(decay),
        .M(M),
        .buffer_current(buffer_current),
        .valid(valid),
        .valid_fifo(valid_fifo),
        .spike(spike),
        .output_new(output_new)
    );

    // Memories
    reg signed [15:0]        buf_cur_mem   [0:NUM_TIMESTEPS-1];
    reg signed [NBITS_VOLTAGE-1:0] v_old_mem [0:NUM_TIMESTEPS-1];
    reg [0:0]                det_mem       [0:NUM_TIMESTEPS-1];
    reg [0:0]                pool_mem      [0:NUM_TIMESTEPS-1];
    reg [0:0]                rec_mem       [0:NUM_TIMESTEPS-1];
    reg [0:0]                spk_exp_mem   [0:NUM_TIMESTEPS-1];
    reg signed [NBITS_VOLTAGE-1:0] vnew_exp_mem [0:NUM_TIMESTEPS-1];

    initial begin
        $readmemh("buffer_current.txt",      buf_cur_mem);
        $readmemh("output_old.txt",           v_old_mem);
        $readmemb("detection.txt",            det_mem);
        $readmemb("pooling_spike_enable.txt", pool_mem);
        $readmemb("recurrency.txt",           rec_mem);
        $readmemb("spike_expected.txt",       spk_exp_mem);
        $readmemh("output_new_expected.txt",  vnew_exp_mem);
    end

    // Clock
    always #5 clk = ~clk;

    integer t;
    integer errors = 0;

    initial begin
        clk = 0; rst = 1; en = 0;
        threshold = THR_VAL;
        decay     = DECAY_VAL;
        M         = M_VAL;
        conv_enable = 0;
        last_input_feature = 0;
        recurrency_next = 0;

        #20 rst = 0;
        #10 en = 1;

        for (t = 0; t < NUM_TIMESTEPS; t = t + 1) begin
            buffer_current       = buf_cur_mem[t];
            output_old           = v_old_mem[t];
            detection            = det_mem[t];
            pooling_spike_enable = pool_mem[t];
            recurrency           = rec_mem[t];

            #10;  // 1 clock cycle

            if (spike !== spk_exp_mem[t]) begin
                $display("SPIKE MISMATCH t=%0d: got=%b exp=%b | buf_cur=%0d v_old=%0d",
                         t, spike, spk_exp_mem[t], $signed(buffer_current), $signed(output_old));
                errors = errors + 1;
            end
            if (output_new !== vnew_exp_mem[t]) begin
                $display("VNEW  MISMATCH t=%0d: got=%0d exp=%0d | buf_cur=%0d v_old=%0d spike=%b",
                         t, $signed(output_new), $signed(vnew_exp_mem[t]),
                         $signed(buffer_current), $signed(output_old), spike);
                errors = errors + 1;
            end
        end

        $display("
=== Test completato: %0d timestep, %0d errori ===", NUM_TIMESTEPS, errors);
        $finish;
    end

endmodule
