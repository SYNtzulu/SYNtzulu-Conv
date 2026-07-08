`timescale 1ns / 1ps

module tb_addr_decoder;

    // Parameters
    parameter MAX_NEURONS = 128;
    parameter MAX_SYNAPSES = 128;
    parameter LAYERS = 4;
    parameter WEIGHT_ADDRESS_SIZE = 13;

    // Inputs
    reg [clogb2(MAX_NEURONS)-1:0] neurons;
    reg [clogb2(MAX_SYNAPSES)-1:0] synapses;
    reg [clogb2(LAYERS-1)-1:0] layer_counter;
    reg [clogb2(MAX_NEURONS/2-1)-1:0] neuron_cnt;
    reg [clogb2(MAX_SYNAPSES/4-1)-1:0] spike_rd_addr;

    // Output
    wire [WEIGHT_ADDRESS_SIZE-1:0] weight_rd_addr;

    // Instantiate the module
    weight_rd_addr_decoder #(
        .MAX_NEURONS(MAX_NEURONS),
        .MAX_SYNAPSES(MAX_SYNAPSES),
        .LAYERS(LAYERS),
        .WEIGHT_ADDRESS_SIZE(WEIGHT_ADDRESS_SIZE)
    ) uut (
        .neurons(neurons),
        .synapses(synapses),
        .layer_counter(layer_counter),
        .neuron_cnt(neuron_cnt),
        .spike_rd_addr(spike_rd_addr),
        .weight_rd_addr(weight_rd_addr)
    );

    // Function to calculate clogb2
    function integer clogb2(input integer value);
        integer i;
        begin
            clogb2 = 0;
            for (i = value - 1; i > 0; i = i >> 1)
                clogb2 = clogb2 + 1;
        end
    endfunction

    // Testbench logic
    initial begin

        $dumpfile("tb.vcd"); 
        $dumpvars(10,tb_addr_decoder); 

        // Initialize inputs
        neurons = 0;
        synapses = 0;
        layer_counter = 0;
        neuron_cnt = 0;
        spike_rd_addr = 0;

        // Apply test cases
        #10 neurons = 7; synapses = 15; layer_counter = 2; neuron_cnt = 3; spike_rd_addr = 1;
        #10 neurons = 31; synapses = 63; layer_counter = 1; neuron_cnt = 7; spike_rd_addr = 3;
        #10 neurons = 127; synapses = 127; layer_counter = 3; neuron_cnt = 15; spike_rd_addr = 7;

        // Finish simulation
        #10 $finish;
    end

    // Monitor output
    initial begin
        $monitor("Time=%0t | neurons=%0d, synapses=%0d, layer_counter=%0d, neuron_cnt=%0d, spike_rd_addr=%0d | weight_rd_addr=%0b",
                 $time, neurons, synapses, layer_counter, neuron_cnt, spike_rd_addr, weight_rd_addr);
    end

endmodule