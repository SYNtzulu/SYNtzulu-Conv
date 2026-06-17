`timescale 1ns / 1ps

module integrator_and_fifo #(
    parameter DEPTH = 256,
    parameter WIDTH = 25,
    parameter MAX_INPUT_FEATURE = 16,
    parameter DECAY_THR_FILE = ""
    )(
    input clk, rst, en, detection,
    input reset_potential,
    input fix_cnt, 
    input [7:0] square_dim_output_feature,
    input conv_enable,
    input dense_enable,
    input pooling_spike_enable,
    input first_input_feature,
    input [13:0] decay,
    input [WIDTH-1:0] stimolo,
    input [WIDTH-1:0] threshold,
    input last_input_feature,

    output valid,
    output spike,
    output [WIDTH-1:0] output_new,
    input clear_counter,
    
    input layer_integrated,
    input recurrency_next,
    input recurrency,
    input output_feature_integrated
    );
    
    wire [WIDTH-1:0] output_old;
    wire [31:0] dec_thr;
	
	
    wire [13:0] dec;
    wire [WIDTH-1:0] thr;

    // DECAY AND THRESHOLD PER LAYER
    dec_thr_mem #(
        .DATA_WIDTH(32), 
        .DEPTH(DEPTH),
        .DECAY_THR_FILE(DECAY_THR_FILE)
    ) dec_thr_mem_i (
        .clk(clk),
        .rst(rst),

        .rden(output_feature_integrated),
        .DO(dec_thr),
        .clear_counter(clear_counter),

        .layer_integrated(layer_integrated),
        .recurrency_next(recurrency_next)
    ); 

	
	assign dec = dec_thr[31:16];
	assign thr   = dec_thr[15: 0];


    // FIFO
    bram_fifo #(
        .DATA_WIDTH(WIDTH), 
        .DEPTH(DEPTH)
    ) fifo_i (
        .clk(clk),
        .rst(rst),
        .reset_potential(reset_potential),
        .fix_cnt(fix_cnt), 
        .square_dim_output_feature(square_dim_output_feature),
        .DI(output_new),
        .rden(en),
        .wren(valid_fifo),
        .DO(output_old),
        .clear_counter(clear_counter),
        .last_input_feature(conv_enable ? last_input_feature : 1'b1),
        .layer_integrated(layer_integrated),
        .recurrency_next(recurrency_next),
        .recurrency(recurrency)
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
        .pooling_spike_enable(pooling_spike_enable),
        .first_input_feature(first_input_feature),
        .output_old(output_old),
        .decay(dec),
        .stimolo(stimolo_d),
        .threshold(thr),
        .valid(valid),
        .valid_fifo(valid_fifo),
        .spike(spike),
        .output_new(output_new),
        .recurrency(recurrency),
        .recurrency_next(recurrency_next)
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
