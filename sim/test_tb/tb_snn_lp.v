`timescale 1ns / 1ps

module tb_snn_lp;

    // Parameters
    parameter WIDTH = 16;
    parameter MAX_SYNAPSES = 128;
    parameter MAX_NEURONS = 128;
    parameter LAYERS = 4;
    parameter MAX_DECAY = 4096;
    parameter MAX_THRESHOLD = 65536;
    parameter INSTR_WIDTH = 56;
    parameter INSTR_FILE = "/home/federico/Documents/syntzulu_new/rtl/instruction.bin";
    parameter WEIGHT_DEPTH_12 = 8192;
    parameter WEIGHT_DEPTH_34 = 8192;

    // Clock and reset
    reg clk;
    reg rst;

    // Inputs
    reg en;
    reg [3:0] spike_in;
    reg active_group_in;

    // Outputs
    wire valid;
    wire valid_spike;
    wire [3:0] spike_out;
    wire integrated_neuron;

    // Weight memory 1
    reg [7:0] weight_mem_L1_wren;
    reg [clogb2(WEIGHT_DEPTH_12-1)-1:0] weight_mem_L1_wr_addr;
    reg [15:0] weight_mem_L1_data_in;
    reg weight_mem_L1_ena;

    // Weight memory 2
    reg [7:0] weight_mem_L2_wren;
    reg [clogb2(WEIGHT_DEPTH_12-1)-1:0] weight_mem_L2_wr_addr;
    reg [15:0] weight_mem_L2_data_in;
    reg weight_mem_L2_ena;

    // Weight memory 3
    reg [7:0] weight_mem_L3_wren;
    reg [clogb2(WEIGHT_DEPTH_34-1)-1:0] weight_mem_L3_wr_addr;
    reg [15:0] weight_mem_L3_data_in;
    reg weight_mem_L3_ena;

    // Weight memory 4
    reg [7:0] weight_mem_L4_wren;
    reg [clogb2(WEIGHT_DEPTH_34-1)-1:0] weight_mem_L4_wr_addr;
    reg [15:0] weight_mem_L4_data_in;
    reg weight_mem_L4_ena;

    // Spike memory
    wire [7:0] o_spike_mem_dat;
    reg [7:0] i_spike_mem_adr;
    reg [1:0] i_spike_mem_rd_en;
    reg [1:0] i_spike_mem_wr_en;
    reg [3:0] i_spike_mem_dat;

    // Layers and channels
    reg [clogb2(MAX_SYNAPSES-1)-1:0] snn_input_channels;
    reg [2:0] layers;

    // Output buffer
    reg output_buffer_ren;
    reg [7:0] output_buffer_addr;
    wire [31:0] output_buffer_out;

    // Instantiate the DUT
    snn_lp #(
        .WIDTH(WIDTH),
        .MAX_SYNAPSES(MAX_SYNAPSES),
        .MAX_NEURONS(MAX_NEURONS),
        .MAX_THRESHOLD(MAX_THRESHOLD),
        .LAYERS(LAYERS),
        .INSTR_FILE(INSTR_FILE),
        .MAX_DECAY(MAX_DECAY),
        .INSTR_WIDTH(INSTR_WIDTH),
        .WEIGHT_DEPTH_12(WEIGHT_DEPTH_12),
        .WEIGHT_DEPTH_34(WEIGHT_DEPTH_34)
    ) dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .spike_in(spike_in),
        .active_group_in(active_group_in),
        .valid(valid),
        .valid_spike(valid_spike),
        .spike_out(spike_out),
        .integrated_neuron(integrated_neuron),
        .weight_mem_L1_wren(weight_mem_L1_wren),
        .weight_mem_L1_wr_addr(weight_mem_L1_wr_addr),
        .weight_mem_L1_data_in(weight_mem_L1_data_in),
        .weight_mem_L1_ena(weight_mem_L1_ena),
        .weight_mem_L2_wren(weight_mem_L2_wren),
        .weight_mem_L2_wr_addr(weight_mem_L2_wr_addr),
        .weight_mem_L2_data_in(weight_mem_L2_data_in),
        .weight_mem_L2_ena(weight_mem_L2_ena),
        .weight_mem_L3_wren(weight_mem_L3_wren),
        .weight_mem_L3_wr_addr(weight_mem_L3_wr_addr),
        .weight_mem_L3_data_in(weight_mem_L3_data_in),
        .weight_mem_L3_ena(weight_mem_L3_ena),
        .weight_mem_L4_wren(weight_mem_L4_wren),
        .weight_mem_L4_wr_addr(weight_mem_L4_wr_addr),
        .weight_mem_L4_data_in(weight_mem_L4_data_in),
        .weight_mem_L4_ena(weight_mem_L4_ena),
        .o_spike_mem_dat(o_spike_mem_dat),
        .i_spike_mem_adr(i_spike_mem_adr),
        .i_spike_mem_rd_en(i_spike_mem_rd_en),
        .i_spike_mem_wr_en(i_spike_mem_wr_en),
        .i_spike_mem_dat(i_spike_mem_dat),
        .snn_input_channels(snn_input_channels),
        .layers(layers),
        .output_buffer_ren(output_buffer_ren),
        .output_buffer_addr(output_buffer_addr),
        .output_buffer_out(output_buffer_out)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz clock
    end

    // Testbench logic
    initial begin
        $dumpfile("tb.vcd"); 
        $dumpvars(10,tb_snn_lp); 
        // Initialize inputs
        rst = 1;
        en = 0;
        spike_in = 0;
        active_group_in = 0;
        weight_mem_L1_wren = 0;
        weight_mem_L1_wr_addr = 0;
        weight_mem_L1_data_in = 0;
        weight_mem_L1_ena = 0;
        weight_mem_L2_wren = 0;
        weight_mem_L2_wr_addr = 0;
        weight_mem_L2_data_in = 0;
        weight_mem_L2_ena = 0;
        weight_mem_L3_wren = 0;
        weight_mem_L3_wr_addr = 0;
        weight_mem_L3_data_in = 0;
        weight_mem_L3_ena = 0;
        weight_mem_L4_wren = 0;
        weight_mem_L4_wr_addr = 0;
        weight_mem_L4_data_in = 0;
        weight_mem_L4_ena = 0;
        i_spike_mem_adr = 0;
        i_spike_mem_rd_en = 0;
        i_spike_mem_wr_en = 0;
        i_spike_mem_dat = 0;
        snn_input_channels = 0;
        layers = 0;
        output_buffer_ren = 0;
        output_buffer_addr = 0;

        // Reset sequence
        #10 rst = 0;
        #10 rst = 1;

        // Test stimulus
        #20 en = 1;
        spike_in = 4'b1010;
        active_group_in = 1;

        // Add more test cases as needed
        #100 $finish;
    end

    // Function to calculate clogb2
    function integer clogb2(input integer value);
        integer i;
        begin
            clogb2 = 0;
            for (i = value - 1; i > 0; i = i >> 1)
                clogb2 = clogb2 + 1;
        end
    endfunction

endmodule