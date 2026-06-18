`timescale 1ns / 1ps

//modifico il modulo togliendo i parametri dei layer e passando il layer come ingresso

module neuron_lp#(
    parameter DEPTH = 256, // è il numero totale di neuroni //TODO non lo sappiamo a priori
    parameter WIDTH = 25, 
    parameter WEIGHTS = 8,
    parameter MAX_INPUT_FEATURE = 16,
    parameter DECAY_THR_FILE = ""
    )(
    input clk, rst, en,
    input reset_potential,
  input fix_cnt, 
  input [7:0] square_dim_output_feature,
    input conv_enable,
    input dense_enable,
    input pooling_spike_enable,
    input first_input_feature,
    input last_input_feature,
    input new_inference_start,
    input [2*(WEIGHTS)-1:0] synaptic_current,
    input detection,
    input clear_counter_fifo,
    
    output spike_s,
    output voltage_ready,
    output [WIDTH-1:0] voltage,
    input layer_integrated,
    input recurrency_next,
    input recurrency,
    input output_feature_integrated,
    input [clogb2(MAX_INPUT_FEATURE)-1:0] num_input_feature,
    input  [11:0] M,
    input [15:0] reset_recurrency,
    input first_layer_no_spike,

    // scrittura decay/threshold mem (caricamento esterno)
    input decay_wren,
    input [clogb2(DEPTH-1)-1:0] decay_wr_addr,
    input [31:0] decay_data_in,
    input decay_ena
    );

    localparam CURRENT_WIDTH = 2*(WEIGHTS+1);

    wire [WIDTH-1:0] current;
    wire [WIDTH-1:0] synaptic_current_ext;
    //wire spike_s;
    //assign synaptic_current_ext = {{(WIDTH-CURRENT_WIDTH){synaptic_current[CURRENT_WIDTH-1]}},synaptic_current};
        
    //integrator_and_fifo
    integrator_and_fifo_snnTorch
    #(
      .DEPTH(DEPTH),
      .WIDTH(WIDTH),
      .MAX_INPUT_FEATURE(MAX_INPUT_FEATURE),
      .DECAY_THR_FILE(DECAY_THR_FILE)
    ) 
    Voltage_i 
    (
      .clk(clk),
      .rst(rst),
      .en(en),
      .reset_potential(reset_potential),
      .fix_cnt(fix_cnt), 
      .square_dim_output_feature(square_dim_output_feature),
      .detection(detection),
      .conv_enable(conv_enable),
      .dense_enable(dense_enable),
      .pooling_spike_enable(pooling_spike_enable),
      .first_input_feature(first_input_feature), 
      .last_input_feature(last_input_feature),
      .stimolo(synaptic_current),
      .valid(voltage_ready),
      .spike(spike_s),
      .output_new(voltage),
      .clear_counter(new_inference_start),
      .layer_integrated(layer_integrated),
      .recurrency_next(recurrency_next),
      .recurrency(recurrency),
      .output_feature_integrated(output_feature_integrated),
      .num_input_feature(num_input_feature),
      .M(M),
      .reset_recurrency(reset_recurrency),
      .first_layer_no_spike(first_layer_no_spike),
      .decay_wren(decay_wren),
      .decay_wr_addr(decay_wr_addr),
      .decay_data_in(decay_data_in),
      .decay_ena(decay_ena)
      //.set_address(set_address)
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
