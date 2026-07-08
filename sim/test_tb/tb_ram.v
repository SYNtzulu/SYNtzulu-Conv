`timescale 1ns/1ps

module tb_SB_RAM_instruction;

    // Parameters
    parameter RAM_WIDTH = 16;
    parameter INSTR_WIDTH = 64;
    parameter INSTR_DEPTH = 16;
    parameter INSTR_FILE = "/home/federico/Documents/syntzulu_new/rtl/instruction.hex";

    // Testbench signals
    reg clk;
    reg rst;
    reg en;
    reg new_layer;
    wire [63:0] instruction;
    wire valid;

    // Instantiate the DUT (Device Under Test)
    SB_RAM_instruction #(
        .RAM_WIDTH(RAM_WIDTH),
        .INSTR_WIDTH(INSTR_WIDTH),
        .INSTR_DEPTH(INSTR_DEPTH),
        .INSTR_FILE(INSTR_FILE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .new_layer(new_layer),
        .instruction(instruction),
        .valid(valid)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz clock
    end

    // Testbench logic
    initial begin
        $dumpfile("tb.vcd"); 
        $dumpvars(10,tb_SB_RAM_instruction); 
        // Initialize signals
        rst = 1;
        en = 0;
        new_layer = 0;

        // Reset the DUT
        #20;
        rst = 0;

        // Test case 1: Enable reading
        #10;
        en = 1;
        #100;
        en = 0;

        // Test case 2: Trigger new_layer
        #50;
        new_layer = 1;
        #10;
        new_layer = 0;

        // Test case 3: Wait and observe
        #200;

        // Finish simulation
        $finish;
    end

    // Monitor outputs
    initial begin
        $monitor("Time: %0t | instruction: %h | valid: %b", $time, instruction, valid);
    end

endmodule