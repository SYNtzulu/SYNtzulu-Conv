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
    initial #1 rst = 0;
    
    reg [15:0] input_feature_row=16'h4000;
    wire [3:0][3:0] spike_address;
    wire input_feature_finish;


    conv_controll dut(
    	.clk(clk),
    	.en(en),
        .rst(rst),
    	.stride (1),
        .new_conv(0),
        .dim_kernel(3),
    	.dim_input_feature(4),
    	.input_feature_row(input_feature_row),
    	.spike_address(spike_address),
        .input_feature_finish(input_feature_finish)
	);


    integer i = 0;
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(10,tb);
        #2 input_feature_row=16'hA000;
        #1 input_feature_row=16'h2000;
        #2 en=1;
        #0.8 en=0;
        #4 input_feature_row=16'h8000;
        #100;
        $finish;
    end

endmodule