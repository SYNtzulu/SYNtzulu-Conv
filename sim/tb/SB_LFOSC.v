`timescale 1ns/1ps

module SB_LFOSC( 
	input CLKLFPU, 
	input CLKLFEN, 
	output CLKLF 
); 

reg clk = 0; 
always #50000 clk <= ~clk; 
assign CLKLF = clk; 

endmodule