`timescale 1ns / 1ps

module tb_layer_lp;

    // Parameters
    parameter WIDTH = 25;
    parameter MAX_SYNAPSES = 256;
    parameter MAX_NEURONS = 256;
    parameter MAX_DECAY = 4096;
    parameter INSTR_WIDTH = 54;
    parameter LAYERS = 4;
    parameter WEIGHT_DEPTH = 8192;

    // Inputs
    reg clk;
    reg rst;
    reg en;
    reg [3:0] spike_in;
    reg active_group_in;
    reg [clogb2(MAX_DECAY-1)-1:0] current_decay;
    reg [clogb2(MAX_DECAY-1)-1:0] voltage_decay;
    reg [WIDTH-1:0] threshold;
    reg [clogb2(WEIGHT_DEPTH-1)-1:0] weight_rd_addr;
    reg acc_clear;
    reg acc_clear_and_go;
    reg [clogb2(LAYERS-1)-1:0] layer_id;
    reg [7:0] weight_mem_L1_wren;
    reg [clogb2(WEIGHT_DEPTH-1)-1:0] weight_mem_L1_wr_addr;
    reg [16-1:0] weight_mem_L1_data_in;
    reg weight_mem_L1_ena;
    reg [7:0] weight_mem_L2_wren;
    reg [clogb2(WEIGHT_DEPTH-1)-1:0] weight_mem_L2_wr_addr;
    reg [16-1:0] weight_mem_L2_data_in;
    reg weight_mem_L2_ena;

    // Outputs
    wire convolution_pipe_full;
    wire valid;
    wire [1:0] spike_out;
    wire active_group_out;
    wire valid_potential;
    wire signed [WIDTH-1:0] neuron_lp_voltage;
    wire integrated_neuron;
    wire [16-1:0] weight_mem_L1_data_out;
    wire [16-1:0] weight_mem_L2_data_out;
    wire [7:0] weight_debug;
    wire weight_en_debug;

    // Instantiate the Unit Under Test (UUT)
    layer_lp #(
        .WIDTH(WIDTH),
        .MAX_SYNAPSES(MAX_SYNAPSES),
        .MAX_NEURONS(MAX_NEURONS),
        .MAX_DECAY(MAX_DECAY),
        .INSTR_WIDTH(INSTR_WIDTH),
        .LAYERS(LAYERS),
        .WEIGHT_DEPTH(WEIGHT_DEPTH)
    ) uut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .spike_in(spike_in),
        .active_group_in(active_group_in),
        .current_decay(current_decay),
        .voltage_decay(voltage_decay),
        .threshold(threshold),
        .weight_rd_addr(weight_rd_addr),
        .acc_clear(acc_clear),
        .acc_clear_and_go(acc_clear_and_go),
        .convolution_pipe_full(convolution_pipe_full),
        .layer_id(layer_id),
        .valid(valid),
        .spike_out(spike_out),
        .active_group_out(active_group_out),
        .valid_potential(valid_potential),
        .neuron_lp_voltage(neuron_lp_voltage),
        .integrated_neuron(integrated_neuron),
        .weight_mem_L1_wren(weight_mem_L1_wren),
        .weight_mem_L1_wr_addr(weight_mem_L1_wr_addr),
        .weight_mem_L1_data_in(weight_mem_L1_data_in),
        .weight_mem_L1_data_out(weight_mem_L1_data_out),
        .weight_mem_L1_ena(weight_mem_L1_ena),
        .weight_mem_L2_wren(weight_mem_L2_wren),
        .weight_mem_L2_wr_addr(weight_mem_L2_wr_addr),
        .weight_mem_L2_data_in(weight_mem_L2_data_in),
        .weight_mem_L2_data_out(weight_mem_L2_data_out),
        .weight_mem_L2_ena(weight_mem_L2_ena),
        .weight_debug(weight_debug),
        .weight_en_debug(weight_en_debug)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz clock
    end

    // Testbench logic
    initial begin
        $dumpfile("tb.vcd"); 
        $dumpvars(10,tb_layer_lp); 
        // Initialize inputs
        rst = 1;
        en = 0;
        spike_in = 0;
        active_group_in = 0;
        current_decay = 0;
        voltage_decay = 0;
        threshold = 0;
        weight_rd_addr = 0;
        acc_clear = 0;
        acc_clear_and_go = 0;
        layer_id = 0;
        weight_mem_L1_wren = 0;
        weight_mem_L1_wr_addr = 10;
        weight_mem_L1_data_in = 0;
        weight_mem_L1_ena = 0;
        weight_mem_L2_wren = 0;
        weight_mem_L2_wr_addr = 10;
        weight_mem_L2_data_in = 0;
        weight_mem_L2_ena = 0;

        // Reset sequence
        #10 rst = 0;
        #10 rst = 1;

        // Enable the module
        #10 en = 1;

        // Apply test stimulus
        #20 spike_in = 4'b1010;
        current_decay = 10;
        voltage_decay = 20;
        threshold = 100;

        // Wait for some time
        #100;

        // End simulation
        $stop;
    end

    // Function to calculate clogb2
    function integer clogb2;
        input integer depth;
        begin
            clogb2 = 0;
            while (depth > 0) begin
                clogb2 = clogb2 + 1;
                depth = depth >> 1;
            end
        end
    endfunction

endmodule