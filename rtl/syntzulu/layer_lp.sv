`timescale 1ns / 1ps

module layer_lp
    #(
    parameter WIDTH = 25,
    parameter MAX_SYNAPSES = 256,
    parameter MAX_NEURONS = 256,
    parameter MAX_INPUT_FEATURE = 16,
    parameter DEPTH_FIFO = 1024,
    
    parameter LAYERS = 4, //è pari alla profondità della memoria delle istruzioni

    parameter WEIGHTS_FILE_1 = "weights_1.txt",
    parameter WEIGHTS_FILE_2 = "weights_2.txt",
    parameter WEIGHT_DEPTH = 8192,
    parameter DECAY_THR_FILE = ""
    )
    (
    input clk, rst,
    input en,
    input [3:0] spike_in,
    input active_group_in,

    input layer_type,
    input new_inference_start,

    //fifo module
    input set_address,

    input write_en_weight_buffer,
    input read_en_weight_buffer,
    input [15:0] spike_address,
    input detection,
    input reset_potential,
    input fix_cnt, 
    input [7:0] square_dim_output_feature,

    input [clogb2(WEIGHT_DEPTH-1)-1:0] weight_rd_addr,
    input acc_clear, acc_clear_and_go,
    output convolution_pipe_full,    
    input [clogb2(LAYERS-1)-1:0] layer_id,

    output valid_spike,
    output spike_out,
    output active_group_out,
    output signed [WIDTH-1:0] neuron_lp_voltage,
	output integrated_neuron,

    //input valid_spike_conv,
    input conv_enable,
    input dense_enable,
    input pooling_spike_enable,
    input first_input_feature,
    input last_input_feature,

    input en_conv_spike,
    input en_conv,
    
    input weight_mem_L1_wren,
    input [clogb2(WEIGHT_DEPTH-1)-1:0] weight_mem_L1_wr_addr,
    input [31:0] weight_mem_L1_data_in,
    input weight_mem_L1_ena,
    output [7:0] weight_debug,
    output weight_en_debug,
    output weights_buffer_ready,

    input layer_integrated,
    input recurrency_next,
    input recurrency,
    input output_feature_integrated,
    input [clogb2(MAX_INPUT_FEATURE)-1:0] num_input_feature,
    input [11:0] M,
    input [15:0] reset_recurrency,
    input first_layer_no_spike
    );

    assign weight_en_debug = en;
    assign weight_debug = weight_rd_addr[7:0]; //weights_out_1[7:0];
    assign valid_spike = integrated_neuron && last_input_feature;

    /////////////////////////////////////////////////////////////////
    //               _       _     _                               //
    // __      _____(_) __ _| |__ | |_   _ __ ___   ___ _ __ ___   //
    // \ \ /\ / / _ \ |/ _` | '_ \| __| | '_ ` _ \ / _ \ '_ ` _ \  //
    //  \ V  V /  __/ | (_| | | | | |_  | | | | | |  __/ | | | | | //
    //   \_/\_/ \___|_|\__, |_| |_|\__| |_| |_| |_|\___|_| |_| |_| //
    //                 |___/                                       //
    /////////////////////////////////////////////////////////////////   

    localparam WEIGHT = 8;  

    wire [31:0] weights_dense;
    wire [31:0] weights_conv;

    BRAM_singlePort_readFirst #(
        .RAM_WIDTH(32),                        // Specify RAM data width
        .RAM_DEPTH(WEIGHT_DEPTH),                      // Specify RAM depth (number of entries)
        .RAM_PERFORMANCE("HIGH_PERFORMANCE"),  // Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
        .INIT_FILE(WEIGHTS_FILE_1)             // Specify name/location of RAM initialization file if using one (leave blank if not)
    )weight_mem_1(
        .addra(weight_mem_L1_wr_addr),         // Port A address bus, driven by axi bus
        .addrb(weight_rd_addr),                 // Port B address bus, it goes in the accumulator
        .dina(weight_mem_L1_data_in),          // Port A RAM input data, driven by axi bus

        .clk(clk),                             // Clock
        .wea(weight_mem_L1_wren),              // Port A write enable

        .ena(weight_mem_L1_ena),               // Port A RAM Enable, for additional power savings, disable port when not in use
        .enb(1'b1),                            // Port B RAM Enable, for additional power savings, disable port when not in use
        .rst(rst),                             // Port A and B output reset (does not affect memory contents)

        .regceb(1'b1),                         // Port B output register enable
        

        .doutb(weights_dense)                   // Port B RAM output data
    );



    ///////////////////////////////////////////////////////////
    //                            _       _   _              //
    //   ___ ___  _ ____   _____ | |_   _| |_(_) ___  _ __   //
    //  / __/ _ \| '_ \ \ / / _ \| | | | | __| |/ _ \| '_ \  //
    // | (_| (_) | | | \ V / (_) | | |_| | |_| | (_) | | | | //
    //  \___\___/|_| |_|\_/ \___/|_|\__,_|\__|_|\___/|_| |_| //
    //                                                       //
    ///////////////////////////////////////////////////////////

    weight_buffer weight_buffer_i
    (
        .clk(clk), 
        .rst(rst), 
        .conv_enable(conv_enable),
        .write_en(write_en_weight_buffer),
        .weight_in(weights_dense),
        .spike_address(spike_address),
        .weight_out(weights_conv),
        .weights_ready(weights_buffer_ready)
    );


    ///////////////////////////////////////////////////////////
    //                            _       _   _              //
    //   ___ ___  _ ____   _____ | |_   _| |_(_) ___  _ __   //
    //  / __/ _ \| '_ \ \ / / _ \| | | | | __| |/ _ \| '_ \  //
    // | (_| (_) | | | \ V / (_) | | |_| | |_| | (_) | | | | //
    //  \___\___/|_| |_|\_/ \___/|_|\__,_|\__|_|\___/|_| |_| //
    //  _____                               _ _              //
    //    __/  __      __ __  __  ___ _ __ (_) | _____       //
    //  \ \    \ \ /\ / / \ \/ / / __| '_ \| | |/ / _ \      //
    //  / /__   \ V  V /   >  <  \__ \ |_) | |   <  __/      //
    //  _____\   \_/\_/   /_/\_\ |___/ .__/|_|_|\_\___|      //
    //                               |_|                     //
    ///////////////////////////////////////////////////////////

    // Spikes and weights are convolved: multiplied (by logic-and) and accumulated (5-way accumulator)

    wire [2*(WEIGHT+1)-1:0] stimulus;
    wire [31:0] weights;
    assign weights = conv_enable ? weights_conv : weights_dense; // 32-bit signed weight
    
    conv #(
        .WEIGHTS(4),          // Number of addends
        .DATA_WIDTH(WEIGHT)   // Width of the Adders
    )conv_i(
        .clk(clk), .rst(rst), .en(en_conv_spike), 
        .en_conv(en_conv),
        .dense_enable(dense_enable),
        .acc_clear_and_go(acc_clear_and_go), .acc_clear(acc_clear),
        .weights_in(weights),
        .spikes(spike_in),
        
        .out(stimulus),
        .valid(convolution_pipe_full)
    );

    //////////////////////////////////////////////
    //     _   _                                //
    //    | \ | | ___ _   _ _ __ ___  _ __      //
    //    |  \| |/ _ \ | | | '__/ _ \| '_ \     //
    //    | |\  |  __/ |_| | | | (_) | | | |    //
    //    |_| \_|\___|\__,_|_|  \___/|_| |_|    //
    //    ___                  _   ____  ____   //
    //   |  _|  __ _ _ __   __| | / ___||  _ \  //
    //   | |   / _` | '_ \ / _` | \___ \| | | | //
    //  _| |  | (_| | | | | (_| |  ___) | |_| | //
    // |___|   \__,_|_| |_|\__,_| |____/|____/  //
    //                                          //
    //////////////////////////////////////////////

    neuron_lp #(
        .DEPTH(DEPTH_FIFO),
        .WIDTH(WIDTH),
        .WEIGHTS(WEIGHT),
        .MAX_INPUT_FEATURE(MAX_INPUT_FEATURE),
        .DECAY_THR_FILE(DECAY_THR_FILE)
    )neuron_lp_i(
        .clk(clk), .rst(rst), .en(acc_clear_and_go),    
        .reset_potential(reset_potential),        
        .fix_cnt(fix_cnt), 
        .square_dim_output_feature(square_dim_output_feature),
        .new_inference_start(new_inference_start),
        .conv_enable(conv_enable),
        .dense_enable(dense_enable),
        .pooling_spike_enable(pooling_spike_enable),
        .first_input_feature(first_input_feature), 
        .last_input_feature(last_input_feature),
        .synaptic_current(stimulus),
        .detection(detection),

        .spike_s(spike_out),
        .voltage_ready(integrated_neuron),
        .voltage(neuron_lp_voltage),
        
	.layer_integrated(layer_integrated),
	.recurrency_next(recurrency_next),
	.recurrency(recurrency),
	.output_feature_integrated(output_feature_integrated),
	.num_input_feature(num_input_feature),
	.M(M),
	.reset_recurrency(reset_recurrency),
	.first_layer_no_spike(first_layer_no_spike)
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

    function integer max;
      input integer a,b;
        if (a>b)
          max = a;
        else
          max = b;
    endfunction 
    
endmodule

