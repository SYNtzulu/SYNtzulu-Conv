`timescale 1ns / 1ps

module tb_neuron_lp;

    // Parameters
    parameter DEPTH = 256;
    parameter WIDTH = 25;
    parameter WEIGHTS = 8;
    parameter MAX_DECAY = 4096;

    // Inputs
    reg clk;
    reg rst;
    reg en;
    reg [2*(WEIGHTS+1)-1:0] synaptic_current;
    reg [clogb2(MAX_DECAY-1)-1:0] current_decay;
    reg [clogb2(MAX_DECAY-1)-1:0] voltage_decay;
    reg [WIDTH-1:0] threshold;

    // Outputs
    wire valid;
    wire [1:0] spike_p;
    wire active_group;
    wire voltage_ready;
    wire [WIDTH-1:0] voltage;

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz clock
    end

    // Instantiate the Unit Under Test (UUT)
    neuron_lp #(
        .DEPTH(DEPTH),
        .WIDTH(WIDTH),
        .WEIGHTS(WEIGHTS),
        .MAX_DECAY(MAX_DECAY)
    ) uut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .synaptic_current(synaptic_current),
        .current_decay(current_decay),
        .voltage_decay(voltage_decay),
        .threshold(threshold),
        .valid(valid),
        .spike_p(spike_p),
        .active_group(active_group),
        .voltage_ready(voltage_ready),
        .voltage(voltage)
    );

    // Testbench logic
    initial begin
        $dumpfile("tb.vcd"); 
        $dumpvars(10,tb_neuron_lp); 
        // Initialize inputs
        rst = 1;
        en = 0;
        synaptic_current = 0;
        current_decay = 0;
        voltage_decay = 0;
        threshold = 0;

        // Reset the system
        #10 rst = 0;
        #10 rst = 1;

        // Apply test stimulus
        #20 en = 1;
        synaptic_current = 8'hFF;
        current_decay = 10;
        voltage_decay = 15;
        threshold = 25;

        // Wait for some time
        #100;

        // Change inputs
        synaptic_current = 8'hAA;
        current_decay = 20;
        voltage_decay = 30;
        threshold = 50;

        // Wait for some time
        #100;

        // End simulation
        $finish;
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