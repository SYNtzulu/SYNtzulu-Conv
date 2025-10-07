`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 20.12.2023 11:28:53
// Design Name: 
// Module Name: tb_riscv
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module tb;

    // CLOCK DEFINITION
    reg clk = 0;
    reg en=0;
    always
        #0.5 clk = ~clk;
    
    // RESET DEFINITION
    reg rst = 1;
    initial #3.2 rst = 0;
    
    reg [2:0][15:0] input_feature_row=48'b010101010101010101010101010101010101010101010101;
    wire [2:0][2:0] output_kernel;
    reg [1:0] stride = 1;
    reg [2:0] sel_A=0;
    wire finish;

    mux_buffer dut(
    	.clk(clk),
    	.en(en),
        .rst(rst),
    	.stride (stride),
    	.input_feature_row(input_feature_row),
    	.output_kernel(output_kernel),
    	.row_finish(finish)
	);


    integer i = 0;
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(10,tb);
        #2 en=1;
        #0.8 en=0;
        #15;
        $finish;
    end

endmodule