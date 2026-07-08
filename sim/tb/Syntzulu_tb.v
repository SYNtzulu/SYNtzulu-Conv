`timescale 1ns / 1ps

module syntzulu_tb;

    // Parameters
    parameter ENCODING_BYPASS = 0;
    parameter CHANNELS = 128;
    parameter ORDER = 2;
    parameter WINDOW = 8192;
    parameter REF_PERIOD = 16;
    parameter DW = 15;
    parameter WIDTH = 16;
    parameter MAX_SYNAPSES = 256;
    parameter MAX_NEURONS = 256;
    parameter WEIGHT_DEPTH_12 = 8192;
    parameter WEIGHT_DEPTH_34 = 8192;

    // Inputs
    reg clk_enc;
    reg clk_snn;
    reg rst;
    reg en;
    reg signed [15:0] data_in;
    reg detect;
    reg encoding_bypass;
    reg [7:0] weight_mem_L1_wren;
    reg [clogb2(WEIGHT_DEPTH_12-1)-1:0] weight_mem_L1_wr_addr;
    reg [15:0] weight_mem_L1_data_in;
    reg weight_mem_L1_ena;
    reg [7:0] weight_mem_L2_wren;
    reg [clogb2(WEIGHT_DEPTH_12-1)-1:0] weight_mem_L2_wr_addr;
    reg [15:0] weight_mem_L2_data_in;
    reg weight_mem_L2_ena;
    reg [7:0] weight_mem_L3_wren;
    reg [clogb2(WEIGHT_DEPTH_34-1)-1:0] weight_mem_L3_wr_addr;
    reg [15:0] weight_mem_L3_data_in;
    reg weight_mem_L3_ena;
    reg [7:0] weight_mem_L4_wren;
    reg [clogb2(WEIGHT_DEPTH_34-1)-1:0] weight_mem_L4_wr_addr;
    reg [15:0] weight_mem_L4_data_in;
    reg weight_mem_L4_ena;
    reg [7:0] i_spike_mem_adr;
    reg [1:0] i_spike_mem_rd_en;
    reg [1:0] i_spike_mem_wr_en;
    reg [3:0] i_spike_mem_dat;
    reg [7:0] i_sample_mem_adr;
    reg i_sample_mem_rd_en;
    reg i_sample_mem_wr_en;
    reg [15:0] i_sample_mem_dat;
    reg [clogb2(MAX_SYNAPSES-1)-1:0] snn_input_channels;
    reg [clogb2(MAX_NEURONS-1)-1:0] neuron_1, neuron_2, neuron_3, neuron_4;
    reg [2:0] layers;
    reg output_buffer_ren;
    reg [7:0] output_buffer_addr;

    // Outputs
    wire valid;
    wire signed [WIDTH-1:0] v;
    wire signed [WIDTH-1:0] f1, f2, f3, f4;
    wire signed [WIDTH-1:0] neuron_lp_voltage;
    wire integrated_neuron;
    wire [15:0] weight_mem_L1_data_out;
    wire [15:0] weight_mem_L2_data_out;
    wire [15:0] weight_mem_L3_data_out;
    wire [15:0] weight_mem_L4_data_out;
    wire [7:0] o_spike_mem_dat;
    wire [15:0] o_sample_mem_dat;
    wire [31:0] output_buffer_out;

    // Instantiate the Unit Under Test (UUT)
    Syntzulu #(
        .ENCODING_BYPASS(ENCODING_BYPASS),
        .CHANNELS(CHANNELS),
        .ORDER(ORDER),
        .WINDOW(WINDOW),
        .REF_PERIOD(REF_PERIOD),
        .DW(DW),
        .WIDTH(WIDTH),
        .MAX_SYNAPSES(MAX_SYNAPSES),
        .MAX_NEURONS(MAX_NEURONS),
        .WEIGHT_DEPTH_12(WEIGHT_DEPTH_12),
        .WEIGHT_DEPTH_34(WEIGHT_DEPTH_34)
    ) uut (
        .clk_enc(clk_enc),
        .clk_snn(clk_snn),
        .rst(rst),
        .en(en),
        .data_in(data_in),
        .detect(detect),
        .encoding_bypass(encoding_bypass),
        .valid(valid),
        .v(v),
        .f1(f1),
        .f2(f2),
        .f3(f3),
        .f4(f4),
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
        .weight_mem_L3_wren(weight_mem_L3_wren),
        .weight_mem_L3_wr_addr(weight_mem_L3_wr_addr),
        .weight_mem_L3_data_in(weight_mem_L3_data_in),
        .weight_mem_L3_data_out(weight_mem_L3_data_out),
        .weight_mem_L3_ena(weight_mem_L3_ena),
        .weight_mem_L4_wren(weight_mem_L4_wren),
        .weight_mem_L4_wr_addr(weight_mem_L4_wr_addr),
        .weight_mem_L4_data_in(weight_mem_L4_data_in),
        .weight_mem_L4_data_out(weight_mem_L4_data_out),
        .weight_mem_L4_ena(weight_mem_L4_ena),
        .o_spike_mem_dat(o_spike_mem_dat),
        .i_spike_mem_adr(i_spike_mem_adr),
        .i_spike_mem_rd_en(i_spike_mem_rd_en),
        .i_spike_mem_wr_en(i_spike_mem_wr_en),
        .i_spike_mem_dat(i_spike_mem_dat),
        .o_sample_mem_dat(o_sample_mem_dat),
        .i_sample_mem_adr(i_sample_mem_adr),
        .i_sample_mem_rd_en(i_sample_mem_rd_en),
        .i_sample_mem_wr_en(i_sample_mem_wr_en),
        .i_sample_mem_dat(i_sample_mem_dat),
        .snn_input_channels(snn_input_channels),
        .neuron_1(neuron_1),
        .neuron_2(neuron_2),
        .neuron_3(neuron_3),
        .neuron_4(neuron_4),
        .layers(layers),
        .output_buffer_ren(output_buffer_ren),
        .output_buffer_addr(output_buffer_addr),
        .output_buffer_out(output_buffer_out)
    );

    // Clock generation
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(10, syntzulu_tb);
        clk_enc = 0;
        forever #5 clk_enc = ~clk_enc;
    end

    initial begin
        clk_snn = 0;
        forever #10 clk_snn = ~clk_snn;
    end

    // Testbench logic
    initial begin
        // Initialize inputs
        rst = 1;
        en = 0;
        data_in = 0;
        detect = 0;
        encoding_bypass = 0;
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
        i_sample_mem_adr = 0;
        i_sample_mem_rd_en = 0;
        i_sample_mem_wr_en = 0;
        i_sample_mem_dat = 0;
        snn_input_channels = 0;
        neuron_1 = 0;
        neuron_2 = 0;
        neuron_3 = 0;
        neuron_4 = 0;
        layers = 0;
        output_buffer_ren = 0;
        output_buffer_addr = 0;

        // Reset sequence
        #20 rst = 0;
        #20 rst = 1;

        // Enable the module
        #20 en = 1;

        // Add further stimulus here
        #1000 $finish;
    end

    // Function to calculate clogb2
    function integer clogb2;
        input integer depth;
        begin
            clogb2 = 0;
            while (depth > 0) begin
                depth = depth >> 1;
                clogb2 = clogb2 + 1;
            end
        end
    endfunction

endmodule