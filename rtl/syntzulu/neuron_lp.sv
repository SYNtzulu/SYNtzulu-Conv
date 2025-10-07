`timescale 1ns / 1ps

//modifico il modulo togliendo i parametri dei layer e passando il layer come ingresso

module neuron_lp#(
    parameter DEPTH = 256, // è il numero totale di neuroni //TODO non lo sappiamo a priori
    parameter WIDTH = 25, 
    parameter WEIGHTS = 8,
    parameter MAX_DECAY = 4096,
    parameter MAX_INPUT_FEATURE = 16
    )(
    input clk, rst, en,
    input conv_enable,
    input dense_enable,
    input first_input_feature,
    input last_input_feature,
    input new_inference_start,
    input [2*(WEIGHTS+1)-1:0] synaptic_current,
    input [clogb2(MAX_DECAY-1)-1:0] current_decay, voltage_decay,
    input detection,
    input [WIDTH-1:0] threshold,
    input [clogb2(MAX_INPUT_FEATURE-1)-1:0] dim_output_feature,
    input clear_counter_fifo,
    
    output spike_s,
    output voltage_ready,
    output [WIDTH-1:0] voltage
    );

    localparam CURRENT_WIDTH = 2*(WEIGHTS+1);

    wire [WIDTH-1:0] current;
    wire [WIDTH-1:0] synaptic_current_ext;
    //wire spike_s;
    //assign synaptic_current_ext = {{(WIDTH-CURRENT_WIDTH){synaptic_current[CURRENT_WIDTH-1]}},synaptic_current};
        
    //integrator_and_fifo #(.DEPTH(DEPTH), .WIDTH(WIDTH)) Current_i (clk, rst, en, 1'b0, current_decay,synaptic_current_ext,threshold,current_ready,current_spike, current);   
    //integrator_and_fifo #(.DEPTH(DEPTH), .WIDTH(WIDTH)) Voltage_i (clk, rst, current_ready, 1'b1, voltage_decay,current,threshold,voltage_ready,spike_s,voltage);   
    integrator_and_fifo #(
      .DEPTH(DEPTH),
      .WIDTH(WIDTH),
      .MAX_INPUT_FEATURE(MAX_INPUT_FEATURE)
    ) Voltage_i (
      .clk(clk),
      .rst(rst),
      .en(en),
      .detection(detection),
      .conv_enable(conv_enable),
      .dense_enable(dense_enable),
      .first_input_feature(first_input_feature), 
      .last_input_feature(last_input_feature),
      .decay(voltage_decay),
      .stimolo(synaptic_current), 
      .threshold(threshold),
      .valid(voltage_ready),
      .spike(spike_s),
      .output_new(voltage),
      .clear_counter(new_inference_start),
      //.set_address(set_address),
      .dim_output_feature(dim_output_feature)
    );
    //wire ready_s2p;

    //assign ready_s2p = conv_enable ? last_input_feature_out && voltage_ready : voltage_ready; // se conv_enable è attivo, allora il ready del s2p è uguale al voltage_ready, altrimenti è sempre 1

    //s2p #(2) s2p_i (clk, rst, ready_s2p, spike_s, spike_p, valid, active_group);    
      
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
