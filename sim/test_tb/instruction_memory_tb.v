`timescale 1ns / 1ps

module instruction_memory_tb;

    // Parameters
    parameter INSTR_MEM_WIDTH = 16;
    parameter TOT_NUM_INSTR   = 6;
    parameter DIM_INSTR       = 64;
    parameter NUM_INSTR       = DIM_INSTR / INSTR_MEM_WIDTH;
    parameter INSTR_MEM_DEPTH = NUM_INSTR * TOT_NUM_INSTR;
    parameter INIT_INSTR_MEM  = "rtl/instruction.hex";

    // Testbench signals
    reg clk;
    reg rst;
    reg clr;
    reg clr_pc;
    reg fetch_instr;
    reg en_pc;
    wire [clogb2(INSTR_MEM_DEPTH-1)-1:0] pc;
    wire valid_instr;
    wire [DIM_INSTR-1:0] instruction_out_full;

    // Instantiate the DUT (Device Under Test)
    instr_mem_block #(
        .INSTR_MEM_WIDTH(INSTR_MEM_WIDTH),
        .TOT_NUM_INSTR(TOT_NUM_INSTR),
        .DIM_INSTR(DIM_INSTR),
        .NUM_INSTR(NUM_INSTR),
        .INSTR_MEM_DEPTH(INSTR_MEM_DEPTH),
        .INIT_INSTR_MEM(INIT_INSTR_MEM)
    ) dut (
        .clk(clk),
        .rst(rst),
        .clr(clr),
        .clr_pc(clr_pc),
        .fetch_instr(fetch_instr),
        .en_pc(en_pc),
        .pc(pc),
        .valid_instr(valid_instr),
        .instruction_out_full(instruction_out_full)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz clock
    end

    // Testbench stimulus
    initial begin
        $dumpfile("tb.vcd"); 
        $dumpvars(10,instruction_memory_tb); 
        // Initialize signals
        rst = 1;
        clr = 0;
        clr_pc = 0;
        fetch_instr = 0;
        en_pc = 0;

        // Reset the DUT
        #10;
        rst = 0;

        // Test case 1: Fetch instructions
        #10;
        fetch_instr = 1;
        en_pc = 1;

        #20;
        fetch_instr = 0;

        // Test case 2: Clear PC
        #10;
        clr_pc = 1;
        #10;
        clr_pc = 0;

        // Test case 3: Clear instruction memory
        #10;
        clr = 1;
        #10;
        clr = 0;

        // End simulation
        #50;
        $finish;
    end

    // Monitor outputs
    initial begin
        $monitor("Time: %0t | PC: %0d | Valid Instr: %b | Instruction Out: %h", 
                 $time, pc, valid_instr, instruction_out_full);
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