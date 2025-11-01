`timescale 1ns/1ps

module SB_HFOSC( 
	input TRIM0, 
	input TRIM1, 
	input TRIM2, 
	input TRIM3, 
	input TRIM4, 
	input TRIM5, 
	input TRIM6, 
	input TRIM7, 
	input TRIM8, 
	input TRIM9, 
	input CLKHFPU, 
	input CLKHFEN, 
	output CLKHF 
); 

parameter TRIM_EN = "0b0"; 
parameter CLKHF_DIV = "0b11"; // "0b00" = 48 MHz, "0b01" = 24 MHz, "0b10" = 12 MHz, "0b11" = 6 MHz 
reg clk = 0; 

always 
	if(CLKHF_DIV == "0b00") 
		#10.42 clk <= ~clk | ~CLKHFEN; 
	else 

	if(CLKHF_DIV == "0b01") 
		#20.83 clk <= ~clk | ~CLKHFEN; 
	else 

	if(CLKHF_DIV == "0b10") 
		#41.67 clk <= ~clk | ~CLKHFEN; 
	else 
	if(CLKHF_DIV == "0b11") 
		#83.3 clk <= ~clk | ~CLKHFEN; 
assign CLKHF = clk; 


endmodule 