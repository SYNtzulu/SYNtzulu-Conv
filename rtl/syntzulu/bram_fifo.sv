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

module bram_fifo#(
parameter DATA_WIDTH = 25, DEPTH = 256
)
(
input clk, rst,
input reset_potential,
input fix_cnt, 
input [7:0] square_dim_output_feature,
input input_feature_finish_out,
input layer_integrated,
input finish_timestep,
input [DATA_WIDTH-1:0] DI,
input rden, wren,
output [DATA_WIDTH-1:0] DO, 
input clear_counter,
input last_input_feature
    );

reg [clogb2(DEPTH-1)-1:0] rd_cnt;
reg [clogb2(DEPTH-1)-1:0] wr_cnt;

reg [7:0] square_dim_output_feature_plus_one;
always @(posedge clk)
    if(rst)
        square_dim_output_feature_plus_one <= 0;
    else 
        square_dim_output_feature_plus_one <= square_dim_output_feature + 1;

// potential mem read pointer
always @(posedge clk)
    if(rst || clear_counter)
        rd_cnt <= 0;
    else if(fix_cnt) // bw IFs the pointer is forced back
        rd_cnt <= rd_cnt - square_dim_output_feature_plus_one;
	// otherwise increment rd pointer by +1
	else if(rden)
        if(rd_cnt < DEPTH-1)
            rd_cnt <= rd_cnt + 1'b1;
        else
            rd_cnt <= 0;

// potential mem write pointer
always @(posedge clk)
    if(rst || clear_counter)
        wr_cnt <= 0;
    else if(fix_cnt) begin // bw IFs the pointer is forced back
        if(wren) // if during IF change a write request arise the address is moved by square_dim_output_feature_plus_one
            wr_cnt <= wr_cnt - square_dim_output_feature;
        else 
            wr_cnt <= wr_cnt - square_dim_output_feature_plus_one;
    end
	// otherwise increment wr pointer by +1
    else if(wren)
        if(wr_cnt < DEPTH-1)
            wr_cnt <= wr_cnt + 1'b1;
        else
            wr_cnt <= 0;

// to reset neuron potential
reg reset_potential_d=0;
always @(posedge clk)
    reset_potential_d <= reset_potential;
assign DO = reset_potential_d ? {DATA_WIDTH{1'b0}} : fifo_out;

wire [DATA_WIDTH-1:0] fifo_out, fifo_out_A, fifo_out_B;


// timestep_pari is one for even timesteps: 0,2,4,etc...
// and it is used to select the first spram block from which 
// the potential is read, which is the last one written by the 
// first layer.
// this only works if the IF are even, otherwise, probably,
// timestep_pari needs to be initialized to 0 instead of 1
// the ping pong bit (active spram) toggles for each input feature
// of each layer and for each dense layer
reg timestep_pari;
always @(posedge clk)
    if(rst)
        timestep_pari <= 1;
    else 
        if(finish_timestep)
            timestep_pari <= !timestep_pari;

reg active_spram;
always @(posedge clk)
    if(rst)
        active_spram <= 0;
    else 
        if(finish_timestep)
            active_spram <= 0;
        else if(layer_integrated)
            active_spram <= timestep_pari;
        else if(input_feature_finish_out)
            active_spram <= !active_spram;

assign fifo_out = active_spram ? fifo_out_A : fifo_out_B;

SPRAM_fifo
#(
  .RAM_WIDTH(DATA_WIDTH),          // Specify RAM data width
  .RAM_DEPTH(DEPTH),               // Specify RAM depth (number of entries)
  .RAM_PERFORMANCE("LOW_LATENCY"), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
  .INIT_FILE("")                   // Specify name/location of RAM initialization file if using one (leave blank if not)
  )
fifo_ram_A
 (
  .addra(wr_cnt),                  // Port A address bus, driven by axi bus
  .addrb(rd_cnt),                  // Port B address bus, it goes in the accumulator
  .dina(DI),                       // Port A RAM input data, driven by axi bus
  .clk(clk),                       // Clock
  .wea(wren),                      // Port A write enable
  .ena(wren),                      // Port A RAM Enable, for additional power savings, disable port when not in use
  .enb(rden),                      // Port B RAM Enable, for additional power savings, disable port when not in use
  //`ifdef USEBRAM   
    .active_spram(!active_spram),
  //`endif  
  .rst(rst),                       // Port A and B output reset (does not affect memory contents)
  .regceb(1'b1),                   // Port B output register enable
  
  .doutb(fifo_out_A)              // Port B RAM output data
    );

SPRAM_fifo
#(
  .RAM_WIDTH(DATA_WIDTH),          // Specify RAM data width
  .RAM_DEPTH(DEPTH),               // Specify RAM depth (number of entries)
  .RAM_PERFORMANCE("LOW_LATENCY"), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
  .INIT_FILE("")                   // Specify name/location of RAM initialization file if using one (leave blank if not)
  )
fifo_ram_B
 (
  .addra(wr_cnt),                  // Port A address bus, driven by axi bus
  .addrb(rd_cnt),                  // Port B address bus, it goes in the accumulator
  .dina(DI),                       // Port A RAM input data, driven by axi bus
  .clk(clk),                       // Clock
  .wea(wren),                      // Port A write enable
  .ena(wren),                      // Port A RAM Enable, for additional power savings, disable port when not in use
  .enb(rden),      // Port B RAM Enable, for additional power savings, disable port when not in use
  //`ifdef USEBRAM   
    .active_spram(active_spram),
  //`endif                         
  .rst(rst),                       // Port A and B output reset (does not affect memory contents)
  .regceb(1'b1),                   // Port B output register enable
  
  .doutb(fifo_out_B)              // Port B RAM output data
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
