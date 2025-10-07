`timescale 1ns / 1ps

module integrator_and_fifo #(
    parameter DEPTH = 256,
    parameter WIDTH = 25,
    parameter MAX_INPUT_FEATURE = 16
    )(
    input clk, rst, en, detection,
    input conv_enable,
    input dense_enable,
    input first_input_feature,
    input [13:0] decay,
    input [WIDTH-1:0] stimolo,
    input [WIDTH-1:0] threshold,
    input last_input_feature,

    output valid,
    output spike,
    output [WIDTH-1:0] output_new,
	input clear_counter,
    input [clogb2(MAX_INPUT_FEATURE-1)-1:0] dim_output_feature 
    );
    
    wire [WIDTH-1:0] output_old;
    
    // FIFO
    bram_fifo #(
        .DATA_WIDTH(WIDTH), 
        .DEPTH(DEPTH)
    ) fifo_i (
        .clk(clk),
        .rst(rst),
        .DI(output_new),
        .rden(en),
        .wren(valid_fifo),
        .DO(output_old),
        .clear_counter(clear_counter),
        .last_input_feature(conv_enable ? last_input_feature : 1)
    ); 
        
    // wait fifo output
    reg en_d;
    reg [WIDTH-1:0] stimolo_d;
    always @(posedge clk)
        if (rst) begin
            en_d <= 0;
            stimolo_d <= 0;
        end
        else begin 
            en_d <= en;
            if(en)
                stimolo_d <= stimolo;
        end
 
  // INTEGRATOR
    integrator #(
        .WIDTH(WIDTH)
    ) integrator_i (
        .clk(clk),
        .rst(rst),
        .en(en_d),
        .detection(detection),
        .conv_enable(conv_enable),
        .first_input_feature(first_input_feature),
        .output_old(output_old),
        .decay(decay),
        .stimolo(stimolo_d),
        .threshold(threshold),
        .valid(valid),
        .valid_fifo(valid_fifo),
        .spike(spike),
        .output_new(output_new)
    );
/* 
        // INTEGRATOR
    integrator #(
        .WIDTH(WIDTH)
    ) integrator_i (
        .clk(clk),
        .rst(rst),
        .en(en_d),
        .detection(detection),
        .output_old(output_old),
        .decay(decay),
        .first_input_feature(first_input_feature),
        .conv_enable(conv_enable),
        .stimolo(stimolo_d),
        .threshold(threshold),
        .valid(valid),
        .valid_fifo(valid_fifo),
        .spike(spike),
        .output_new(output_new)
    );

*/
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
