`timescale 1ns / 1ps

module tb_integrator_conv;

    // Parameters
    parameter WIDTH = 16;

    // Testbench signals
    reg clk;
    reg rst;
    reg en;
    reg detection;
    reg conv_enable;
    reg dense_enable;
    reg last_input_feature;
    reg [WIDTH-1:0] output_old;
    reg [13:0] decay;
    reg [WIDTH-1:0] stimolo;
    reg [WIDTH-1:0] threshold;

    wire valid;
    wire spike;
    wire [WIDTH-1:0] output_new;

    // Instantiate the DUT (Device Under Test)
    integrator_conv #(.WIDTH(WIDTH)) dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .conv_enable(conv_enable),
        .dense_enable(dense_enable),
        .last_input_feature(last_input_feature),
        .output_old(output_old),
        .decay(decay),
        .stimolo(stimolo),
        .threshold(threshold),
        .valid(valid),
        .spike(spike),
        .output_new(output_new)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz clock
    end

    // Test sequence
    initial begin
        // Initialize inputs
        $dumpfile("tb_integrator.vcd"); 
        $dumpvars(10,tb_integrator_conv); 
        rst = 1;
        en = 0;
        detection = 0;
        conv_enable = 0;
        dense_enable = 0;
        last_input_feature = 0;
        output_old = 0;
        decay = 0;
        stimolo = 0;
        threshold = 0;

        // Reset the DUT
        #10 rst = 0;

        // Test case 1: Basic functionality
        #5 en = 1;
        detection = 1;
        conv_enable = 1;
        dense_enable = 0;
        last_input_feature = 0;
        output_old = 16'h1234;
        decay = 14'h0A;
        stimolo = 16'h0050;
        threshold = 16'h0100;
        #20 output_old = output_new;
        #10 output_old = output_new; // Update output_old with new value
        #10 last_input_feature = 1; // Indicate last input feature
        #10 last_input_feature = 0; // Indicate last input feature
        #50;

        // Test case 2: Spike generation
        stimolo = 16'h0200;
        threshold = 16'h0150;

        #50;

        // Test case 3: Reset behavior
        rst = 1;
        #10 rst = 0;

        #50;

        // End simulation
        $finish;
    end

endmodule