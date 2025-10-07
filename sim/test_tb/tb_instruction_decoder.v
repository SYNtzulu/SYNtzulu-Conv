`timescale 1ns / 1ps

module tb_instruction_decoder;

    // Parameters
    parameter INSTR_WIDTH = 80;
    parameter MAX_NEURONS = 256;
    parameter MAX_SYNAPSES = 256;
    parameter MAX_CURRENT_DECAY = 4096;
    parameter MAX_VOLTAGE_DECAY = 4096;
    parameter MAX_THRESHOLD = 65536;

    // Testbench signals
    reg [INSTR_WIDTH-1:0] instr;
    wire [1:0] layer_type;
    wire [$clog2(MAX_NEURONS)-1:0] neuron;
    wire [$clog2(MAX_SYNAPSES)-1:0] synapses;
    wire [$clog2(MAX_CURRENT_DECAY)-1:0] current_decay;
    wire [$clog2(MAX_VOLTAGE_DECAY)-1:0] voltage_decay;
    wire [$clog2(MAX_THRESHOLD)-1:0] threshold;
    wire [$clog2(MAX_SYNAPSES/4-1)-1:0] SYN_G_L2;
    wire [$clog2(MAX_NEURONS*MAX_SYNAPSES/8)-1:0] P;
    wire [$clog2($clog2(MAX_NEURONS/2)-1)-1:0] NEURON_2_LOG;

    // DUT instantiation
    instruction_decoder #(
        .INSTR_WIDTH(INSTR_WIDTH),
        .MAX_NEURONS(MAX_NEURONS),
        .MAX_SYNAPSES(MAX_SYNAPSES),
        .MAX_CURRENT_DECAY(MAX_CURRENT_DECAY),
        .MAX_VOLTAGE_DECAY(MAX_VOLTAGE_DECAY),
        .MAX_THRESHOLD(MAX_THRESHOLD)
    ) dut (
        .instr(instr),
        .layer_type(layer_type),
        .neuron(neuron),
        .synapses(synapses),
        .current_decay(current_decay),
        .voltage_decay(voltage_decay),
        .threshold(threshold),
        .SYN_G_L2(SYN_G_L2),
        .P(P),
        .NEURON_2_LOG(NEURON_2_LOG)
    );

    // Testbench procedure
    initial begin
        $dumpfile("tb.vcd"); 
        $dumpvars(10,tb_instruction_decoder); 
        // Test case 2: Set specific bits in the instruction
        instr = 80'b00010000000010000000000000000011111101011000000000000100110000100000000000111100;
        #10;
        $display("Test 1: instr = %b", instr);
        $display("layer_type = %b, neuron = %b, synapses = %b, current_decay = %b, voltage_decay = %b, threshold = %b, SYN_G_L2 = %b, P = %b, NEURON_2_LOG = %b",
                 layer_type, neuron, synapses, current_decay, voltage_decay, threshold, SYN_G_L2, P, NEURON_2_LOG);

        // Test case 3: Random instruction value
        instr = 80'b00100000000100000000000000000011111101011000000000000100010000110000000001001101;
        #10;
        $display("Test 2: instr = %b", instr);
        $display("layer_type = %b, neuron = %b, synapses = %b, current_decay = %b, voltage_decay = %b, threshold = %b, SYN_G_L2 = %b, P = %b, NEURON_2_LOG = %b",
                 layer_type, neuron, synapses, current_decay, voltage_decay, threshold, SYN_G_L2, P, NEURON_2_LOG);
        // Test case 1: Initialize instruction with all zeros
        instr = 80'b00010000001000000000000000000011111101011000000000000010110001000000000001001100;
        #10;
        $display("Test 3: instr = %b", instr);
        $display("layer_type = %b, neuron = %b, synapses = %b, current_decay = %b, voltage_decay = %b, threshold = %b, SYN_G_L2 = %b, P = %b, NEURON_2_LOG = %b",
                 layer_type, neuron, synapses, current_decay, voltage_decay, threshold, SYN_G_L2, P, NEURON_2_LOG);

        instr = 80'b00000100000100000000000000000011111101011101111111111111110000110000000000110010;
        #10;
        $display("Test 4: instr = %b", instr);
        $display("layer_type = %b, neuron = %b, synapses = %b, current_decay = %b, voltage_decay = %b, threshold = %b, SYN_G_L2 = %b, P = %b, NEURON_2_LOG = %b",
                 layer_type, neuron, synapses, current_decay, voltage_decay, threshold, SYN_G_L2, P, NEURON_2_LOG);

        // End simulation
        $finish;
    end

endmodule