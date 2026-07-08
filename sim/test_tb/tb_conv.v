`timescale 1ns/1ps

module tb_conv;

    // Parameters
    parameter MAX_INPUT_FEATURE = 16;
    parameter MAX_KERNEL = 3;
    parameter MAX_NUMBER_INPUT_FEATURE = 32;
    parameter MAX_NUMBER_OUTPUT_FEATURE = 32;

    // Inputs
    reg clk;
    reg rst;
    reg en;
    reg [1:0] layer_type;
    reg [1:0] stride;
    reg conv_enable;
    reg new_conv;
    reg [clogb2(MAX_KERNEL)-1:0] dim_kernel;
    reg [clogb2(MAX_INPUT_FEATURE)-1:0] dim_input_feature;
    reg [clogb2(MAX_NUMBER_INPUT_FEATURE)-1:0] number_input_feature;
    reg [clogb2(MAX_NUMBER_OUTPUT_FEATURE)-1:0] number_output_feature;
    reg [MAX_INPUT_FEATURE-1:0] input_feature_row;

    // Outputs
    wire [15:0] spike_address;
    wire conv_finish;
    wire write_en_weight_buffer;
    wire read_en_weight_buffer;

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz clock
    end

    // Instantiate the DUT (Device Under Test)
    conv_controll #(
        .MAX_INPUT_FEATURE(MAX_INPUT_FEATURE),
        .MAX_KERNEL(MAX_KERNEL),
        .MAX_NUMBER_INPUT_FEATURE(MAX_NUMBER_INPUT_FEATURE),
        .MAX_NUMBER_OUTPUT_FEATURE(MAX_NUMBER_OUTPUT_FEATURE)
    ) dut (
        .clk(clk),
        .en(en),
        .rst(rst),
        .stride(stride),
        .conv_enable(conv_enable),
        .dim_kernel(dim_kernel),
        .dim_input_feature(dim_input_feature),
        .number_input_feature(number_input_feature),
        .number_output_feature(number_output_feature),
        .input_feature_row(input_feature_row),
        .spike_address(spike_address),
        .conv_finish(conv_finish),
        .write_en_weight_buffer(write_en_weight_buffer),
        .read_en_weight_buffer(read_en_weight_buffer)
    );

    // Testbench logic
    initial begin
        // Initialize inputs

        $dumpfile("tb_conv.vcd"); 
        $dumpvars(10,tb_conv); 
        rst = 1;
        en = 0;
        layer_type = 2'b00;
        stride = 2'b01; // Stride = 1
        conv_enable = 0;
        new_conv = 0;
        dim_kernel = 3; // Kernel size = 3
        dim_input_feature = 4; // 4 input features
        number_input_feature = 4; // 4 input features
        number_output_feature = 4; // 1 output feature
        input_feature_row = 0;

        // Reset the DUT
        #10 rst = 0;

        // Start convolution
        #5 conv_enable = 1;
        new_conv = 1;

        // Provide input feature rows
        input_feature_row = 16'b0001_0000_0000_0000; // Example input row 1
        #10 new_conv = 0;
        input_feature_row = 16'b0010_0000_0000_0000; // Example input row 2
        #10 input_feature_row = 16'b1111_0000_0000_0000; // Example input row 3
        #10 input_feature_row = 16'b0100_0000_0000_0000; // Example input row 4
        #100 input_feature_row = 16'b0010_0000_0000_0000; // Example input row 2
        #10 input_feature_row = 16'b1111_0000_0000_0000; // Example input row 3
        #10 input_feature_row = 16'b0100_0000_0000_0000; // Example input row 4

        // Wait for convolution to finish
        wait(conv_finish);
        #1000;

        // End simulation
        #10 $finish;
    end

    // Function to calculate clogb2
    function integer clogb2(input integer value);
        integer i;
        begin
            value = value - 1;
            for (i = 0; value > 0; i = i + 1)
                value = value >> 1;
            clogb2 = i;
        end
    endfunction

endmodule