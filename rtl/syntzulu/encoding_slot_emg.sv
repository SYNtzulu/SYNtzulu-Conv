`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 23.02.2024 
// Design Name: 
// Module Name: encoding_slot_ieeg
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
//////////////////////////////////////////////////////////////////////////////////


module encoding_slot_emg
#(
    parameter CHANNELS = 128,
    parameter DW = 8
)
(
    input clk, rst,
    input en,
    input signed [DW-1:0] data_in,
    // SPI load della delta mem (soglie per canale)
    input             spi_delta_wen,
    input      [9:0]  spi_delta_waddr,
    input      [15:0] spi_delta_wdata,
    //output [3:0] spike_bin,
    output pos_spike,
    output neg_spike,
    output dm_valid
    //output valid_bin
    //output active_group_out_bin
    );

 localparam SPIKE  = 4;
 localparam CHANNELS_L2 = clogb2(CHANNELS-1);

//////////////////////////////////////////////////////////////////////////////////
//   ____       _ _                              _       _       _              //
//  |  _ \  ___| | |_ __ _   _ __ ___   ___   __| |_   _| | __ _| |_ ___  _ __  //
//  | | | |/ _ \ | __/ _` | | '_ ` _ \ / _ \ / _` | | | | |/ _` | __/ _ \| '__| //
//  | |_| |  __/ | || (_| | | | | | | | (_) | (_| | |_| | | (_| | || (_) | |    //
//  |____/ \___|_|\__\__,_| |_| |_| |_|\___/ \__,_|\__,_|_|\__,_|\__\___/|_|    //
//                                                                              //
//////////////////////////////////////////////////////////////////////////////////


//wire [1:0] dm_spike;

delta_modulator_multichannel #(
	.CHANNELS(CHANNELS),
	.WIDTH(DW)
	) 
	delta_modulator_1 (
	.clk       (clk)      ,
	.rst       (rst)      ,
	.en        (en)       ,
	.samples   (data_in)  ,
	.spi_wen   (spi_delta_wen)  ,
	.spi_waddr (spi_delta_waddr),
	.spi_wdata (spi_delta_wdata),
	.pos_spike (pos_spike),
	.neg_spike (neg_spike),
	.valid     (dm_valid )
	);


//  The following function calculates the address width based on specified RAM depth
function integer clogb2;
  input integer depth;
    for (clogb2=0; depth>0; clogb2=clogb2+1)
      depth = depth >> 1;
endfunction   

endmodule

