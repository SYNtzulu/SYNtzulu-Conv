`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.11.2022 10:58:43
// Design Name: 
// Module Name: fifo
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

module dec_thr_mem #(
parameter DATA_WIDTH = 25, DEPTH = 256, 
parameter RESET_RECURRENCY = 3,         //ATTENTION HARDCODED
parameter DECAY_THR_FILE = "" 
)
(
input clk, rst,

input rden,
output [DATA_WIDTH-1:0] DO, 
input clear_counter,

input layer_integrated,
input recurrency_next,

// porta A di scrittura (caricamento esterno da AXI/TB)
input wren,
input [clogb2(DEPTH-1)-1:0] wr_addr,
input [DATA_WIDTH-1:0] data_in

    );

reg [clogb2(DEPTH-1)-1:0] rd_cnt;


always @(posedge clk)
    if(rst || clear_counter)
        rd_cnt <= 0;
        
    //else if (layer_integrated && recurrency_next) 
    	//rd_cnt <= rd_cnt - RESET_RECURRENCY;

	else if(rden)
        if(rd_cnt < DEPTH-1)
            rd_cnt <= rd_cnt + 1'b1;
        else
            rd_cnt <= 0;


BRAM_singlePort_readFirst
#(
  .RAM_WIDTH(DATA_WIDTH),         
  .RAM_DEPTH(DEPTH),             
  .RAM_PERFORMANCE("LOW_LATENCY"),  
  .INIT_FILE(DECAY_THR_FILE)                 
  )
mem_i
 (
  .addra(wr_addr),
  .addrb(rd_cnt),
  .dina(data_in),
  .clk(clk),
  .wea(wren),
  .ena(wren),
  .enb(1'b1),               
  .rst(rst),                
  .regceb(1'b1),            
  
  .doutb(DO)          
    );



////////////////////////////
//  _               ____  //
// | | ___   __ _  |___ \ //
// | |/ _ \ / _` |   __)  //
// | | (_) | (_| |  / __/ //
// |_|\___/ \__, | |_____ //
//          |___/         //
////////////////////////////
   
//  The following function calculates the address width based on specified RAM depth
function integer clogb2;
  input integer depth;
    for (clogb2=0; depth>0; clogb2=clogb2+1)
      depth = depth >> 1;
endfunction   

endmodule
