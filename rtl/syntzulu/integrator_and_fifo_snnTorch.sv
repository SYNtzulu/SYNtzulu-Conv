`timescale 1ns / 1ps

// Precisione dei bit letta da config.txt (incluso tramite `include `CONFIG_PATH).
// I default qui sotto valgono solo come fallback (es. testbench standalone).
`ifndef NBITS_M
  `define NBITS_M 16
`endif
`ifndef NBITS_THR
  `define NBITS_THR 16
`endif
`ifndef NBITS_DECAY
  `define NBITS_DECAY 16
`endif
`ifndef NBITS_VOLTAGE
  `define NBITS_VOLTAGE 8
`endif
`ifndef NBITS_BUFFER_CURRENT
  `define NBITS_BUFFER_CURRENT 32
`endif

module integrator_and_fifo_snnTorch #(
    parameter DEPTH = 256,
    parameter WIDTH = 25,
    parameter MAX_INPUT_FEATURE = 16,
    parameter DECAY_THR_FILE = "",
    parameter nbits_M       = `NBITS_M,
    parameter nbits_thr     = `NBITS_THR,
    parameter nbits_decay   = `NBITS_DECAY,
    parameter nbits_voltage = `NBITS_VOLTAGE,
    parameter nbits_buffer_current = `NBITS_BUFFER_CURRENT
    )
    (
    input clk, rst, en, detection,
    input reset_potential,
    input fix_cnt, 				//unused 
    input [7:0] square_dim_output_feature,
    input conv_enable,
    input dense_enable,
    input pooling_spike_enable,
    input first_input_feature,
    input [15:0] stimolo,
    input last_input_feature,

    output valid,
    output spike,
    output [nbits_voltage-1:0] output_new,
    input clear_counter,
    
    input layer_integrated,
    input recurrency_next,
    input recurrency,
    input output_feature_integrated,
    input [nbits_M -1 :0] M,
    input [clogb2(MAX_INPUT_FEATURE)-1:0] num_input_feature,
    input [15:0] reset_recurrency,
    input first_layer_no_spike,

    // scrittura decay/threshold mem (caricamento esterno)
    input decay_wren,
    input [clogb2(DEPTH-1)-1:0] decay_wr_addr,
    input [nbits_decay + nbits_thr -1:0] decay_data_in
    );
    
    
    wire [nbits_voltage-1:0] output_old;
    
    wire [nbits_thr + nbits_decay -1:0] dec_thr;
    wire [nbits_decay-1:0] dec;
    wire [nbits_thr-1:0]   thr;
    
    
    wire signed [nbits_buffer_current-1:0] buffer_current;
    reg  signed [nbits_buffer_current-1:0] buffer_current_d;
    reg  signed valid_buffer_current_d;
            
    buffer_current_mem
    #
    (
    	.WIDTH(nbits_buffer_current),
    	.ROW(256)
    )
    buffer_current_mem_i
    (
	.clk(clk),
	.rst(rst), 
	.en(en),
	.num_input_feature(num_input_feature),
	.square_dim_output_feature(square_dim_output_feature),
	.stimolo(stimolo),
	
	.buffer_current(buffer_current), 
	.valid_buffer_current(valid_buffer_current),
	.first_layer_no_spike(first_layer_no_spike)  	
    );
    
    always@(posedge clk) begin
    	if(rst) begin
    		buffer_current_d       <= 0; 
    		valid_buffer_current_d <= 0;
    	end
    	else begin
    		valid_buffer_current_d <= valid_buffer_current;
    		buffer_current_d       <= buffer_current; 
    	end 
    end



    // DECAY AND THRESHOLD PER LAYER
    dec_thr_mem #(
        .DATA_WIDTH(nbits_decay + nbits_thr), 
        .DEPTH(DEPTH),
        .DECAY_THR_FILE(DECAY_THR_FILE)
    ) dec_thr_mem_i (
        .clk(clk),
        .rst(rst),

        .rden(output_feature_integrated),
        .DO(dec_thr),
        .clear_counter(clear_counter),

        .layer_integrated(layer_integrated),
        .recurrency_next(recurrency_next),

        .wren(decay_wren),
        .wr_addr(decay_wr_addr),
        .data_in(decay_data_in)
    );

	// {decay, threshold}
	assign dec = dec_thr[nbits_thr + nbits_decay - 1 : nbits_decay]; //230;
	assign thr = dec_thr[nbits_decay-1: 0]; //3;


    // FIFO
    bram_fifo 
    #(
        .DATA_WIDTH(nbits_voltage), 
        .DEPTH(10496)
    ) fifo_i (
        .clk(clk),
        .rst(rst),
        .reset_potential(reset_potential),
        .fix_cnt(1'b0), 					//unused
        .square_dim_output_feature(square_dim_output_feature), //unused
        .DI(output_new),
        .rden(valid_buffer_current),
        .wren(valid_fifo),
        .DO(output_old),
        .clear_counter(clear_counter),
        //.last_input_feature(conv_enable ? last_input_feature : 1'b1), //unused
        .layer_integrated(layer_integrated),
        .recurrency_next(recurrency_next),
        .recurrency(recurrency),
        .reset_recurrency(reset_recurrency)
    ); 
   

    integrator_snnTorch
    #
    (
    .nbits_M             ( nbits_M       ),
    .nbits_thr           ( nbits_thr     ),
    .nbits_decay         ( nbits_decay   ),
    .nbits_voltage       ( nbits_voltage ),
    .nbits_buffer_current( nbits_buffer_current )
    )
    integrator_i 
    (
        .clk(clk),
        .rst(rst),
        .en(valid_buffer_current_d),
        .detection(detection),
        .conv_enable(conv_enable),
        .pooling_spike_enable(pooling_spike_enable),
        //.last_input_feature(last_input_feature),
        .recurrency(recurrency),
        .recurrency_next(recurrency_next),
        .output_old(output_old),
        .threshold(thr),
        .decay(dec),
        .M(M),
        .buffer_current(buffer_current_d),
        .valid(valid),
        .valid_fifo(valid_fifo),
        .spike(spike),
        .output_new(output_new)
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
