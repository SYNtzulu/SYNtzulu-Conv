`timescale 1ns / 1ps

module snn_lp 
#(
    parameter WIDTH = 26,

	parameter MAX_SYNAPSES  = 128,
	parameter MAX_NEURONS = 128,
	parameter LAYERS = 4, //è pari alla profondità della memoria delle istruzioni
    parameter MAX_DECAY = 4096,
    parameter MAX_THRESHOLD = 65536,
    parameter BASE_ADDRESS_WEIGHTS = 1024,
    //CONV
    parameter MAX_INPUT_FEATURE = 16,
    parameter MAX_KERNEL = 3,
	parameter MAX_NUMBER_INPUT_FEATURE = 32,
	parameter MAX_NUMBER_OUTPUT_FEATURE = 32,

    parameter INSTR_WIDTH = 64,
    parameter INSTR_FILE = "/home/federico/Documents/syntzulu_new/rtl/instruction.hex",

    parameter WEIGHTS_FILE_1 = "/home/sambu/Documents/syntzulu_new/flash/src/weights_1.txt",
    parameter WEIGHTS_FILE_2 = "/home/sambu/Documents/syntzulu_new/flash/src/weights_2.txt",
    parameter WEIGHTS_FILE_3 = "/home/sambu/Documents/syntzulu_new/flash/src/weights_3.txt",
    parameter WEIGHTS_FILE_4 = "/home/sambu/Documents/syntzulu_new/flash/src/weights_4.txt",

    parameter WEIGHT_DEPTH_12 = 8192,
    parameter WEIGHT_DEPTH_34 = 8192
)
    (
    // input
    input clk, rst,
    input en,

    input s1_encoding,
    input s2_encoding,

    // output
    output valid,	
	output valid_spike,
    output [3:0] spike_out,
	output integrated_neuron,

    // weight mem 1
    input [7:0] weight_mem_L1_wren,
    input [clogb2(WEIGHT_DEPTH_12-1)-1:0] weight_mem_L1_wr_addr,
    input [16-1:0] weight_mem_L1_data_in,
    input weight_mem_L1_ena,

    // weight mem 2
    input [7:0] weight_mem_L2_wren,
    input [clogb2(WEIGHT_DEPTH_12-1)-1:0] weight_mem_L2_wr_addr,
    input [16-1:0] weight_mem_L2_data_in,
    input weight_mem_L2_ena,

    // weight mem 3
    input [7:0] weight_mem_L3_wren,
    input [clogb2(WEIGHT_DEPTH_34-1)-1:0] weight_mem_L3_wr_addr,
    input [16-1:0] weight_mem_L3_data_in,
    input weight_mem_L3_ena,

    // weight mem 4
    input [7:0] weight_mem_L4_wren,
    input [clogb2(WEIGHT_DEPTH_34-1)-1:0] weight_mem_L4_wr_addr,
    input [16-1:0] weight_mem_L4_data_in,
    input weight_mem_L4_ena,

	//spike mem 1 & 2
	output wire [7:0] o_spike_mem_dat,
	input wire [7:0] i_spike_mem_adr,
	input wire [1:0] i_spike_mem_rd_en,
	input wire [1:0] i_spike_mem_wr_en,
	input wire [3:0] i_spike_mem_dat,

	// # layers and channels
	input wire [clogb2(MAX_SYNAPSES-1)-1:0] snn_input_channels,
	input wire [2:0] layers,

	// output buffer access
	input output_buffer_ren,
	input [7:0] output_buffer_addr,
	output [31:0] output_buffer_out,
    input input_buffer_valid
    );

localparam LAYERS_LOG2 = clogb2(LAYERS-1);
localparam TOTAL_NEURONS = 4*MAX_NEURONS; 

localparam MAX_SYNAPSES_DENSE = 128;

localparam WEIGHT_ADDRESS_SIZE = clogb2(MAX_NEURONS/2-1) + clogb2(MAX_SYNAPSES_DENSE/4-1) + clogb2(LAYERS-1);

// interconnection signals
wire s1, s2;

/* PROGRAMM COUNTER */
wire [INSTR_WIDTH-1:0] current_instr;
reg input_buffer_valid_d;

always @(posedge clk)
    if (rst)
        input_buffer_valid_d <= 0;
    else
        input_buffer_valid_d <= input_buffer_valid;

assign start_instruction =  (input_buffer_valid) && !input_buffer_valid_d;

localparam INSTR_DEPTH = (LAYERS * 4);

instruction_memory #(
    .INSTR_WIDTH(INSTR_WIDTH),
    .INSTR_DEPTH(INSTR_DEPTH),
    .INSTR_FILE(INSTR_FILE)
) instruction_memory (
    .clk(clk),
    .rst(rst),
    .new_inference_start(start_instruction),
    .en(layer_integrated_conv || (dense_enable && layer_integrated)),
    .instruction(current_instr)
);

/* INSTRUCTION DECODER*/

wire [1:0] layer_type;
wire [clogb2(MAX_NEURONS)-1:0] neuron;
wire [clogb2(MAX_SYNAPSES)-1:0] synapses;
wire [clogb2(MAX_DECAY)-1:0] current_decay;
wire [clogb2(MAX_DECAY)-1:0] voltage_decay;
wire [clogb2(MAX_THRESHOLD)-1:0] threshold;
wire [3:0] bit_for_spike;
wire [clogb2(MAX_INPUT_FEATURE):0] number_input_feature;
wire [clogb2(MAX_INPUT_FEATURE):0] number_output_feature;
wire [clogb2(MAX_INPUT_FEATURE):0] size_input_feature;
wire [1:0] stride;
wire [clogb2(MAX_INPUT_FEATURE)-1:0] kernel_size;
wire [4:0] next_dim_input_feature;
wire dense_next;
wire [10:0] SYNAPSES_instr;

instruction_decoder #(
    .INSTR_WIDTH(INSTR_WIDTH)
    )ID_current(
    .instr(current_instr),
    .layer_type(layer_type),
    .neuron(neuron),
    .synapses(synapses),
    .next_dim_input_feature(next_dim_input_feature),
    .voltage_decay(voltage_decay),
    .threshold(threshold),
    .bit_for_spike(bit_for_spike),
    .number_input_feature(number_input_feature),
    .number_output_feature(number_output_feature),
    .size_input_feature(size_input_feature),
    .stride(stride),
    .kernel_size(kernel_size),
    .dense_next(dense_next),
    .SYNAPSES (SYNAPSES_instr)
    );

/*
  _     ____            _     _ 
 | |   |  _ \          | |   / |
 | |   | |_) |  _____  | |   | |
 | |___|  __/  |_____| | |___| |
 |_____|_|             |_____|_|
                                
*/    
wire signed [WIDTH-1:0] voltage_1;
wire acc_clear_and_go;
wire acc_clear;
wire last_input_feature_out;
wire convolution_valid_dense;
wire valid_spike_1, valid_spike_2;

assign valid_spike_1 = dense_enable ? integrated_neuron_1 : integrated_neuron_1 && last_input_feature_out;
assign valid_spike_2 = dense_enable ? integrated_neuron_2 : integrated_neuron_2 && last_input_feature_out;

assign acc_clear_and_go = conv_enable ? convolution_pipe_full : convolution_valid;

wire en_conv_spike_conv;

assign en_conv_spike_conv = layer_enable_dd && weights_buffer_ready;

wire en_conv_spike = conv_enable ? en_conv_spike_conv : layer_enable_dd;

// PIPELINE
wire detection_out_pipe;
wire first_input_feature_out;
wire detection_computed;
wire first_input_feature_computed;

assign first_input_feature_computed = conv_enable ? first_input_feature_out : 0;

lif_pipe lif_pipe_i (
    .clk(clk),
    .rst(rst),
    .detection(spike_check),
    .first_input_feature(first_input_feature),
    .last_input_feature(last_input_feature),
    .en_L2(en_L2),
    .detection_out(detection_out_pipe),
    .first_input_feature_out(first_input_feature_out),
    .last_input_feature_out(last_input_feature_out),
    .en_L2_out(en_L2_out)
);

assign detection_computed = conv_enable ? detection_out_pipe : spike_check;

layer_lp
    #(
    .WIDTH(WIDTH),
    .MAX_SYNAPSES(MAX_SYNAPSES),
    .MAX_NEURONS(MAX_NEURONS/2),
    .MAX_DECAY(MAX_DECAY),
    .MAX_INPUT_FEATURE(MAX_INPUT_FEATURE),

	.LAYERS(LAYERS),

    .WEIGHTS_FILE_1(WEIGHTS_FILE_1),
	.WEIGHTS_FILE_2(WEIGHTS_FILE_2),
    .WEIGHT_DEPTH(WEIGHT_DEPTH_12)
    )
layer_lp_l1_i
    (
    .clk(clk), .rst(rst),
    .en(layer_enable_dd),
    .spike_in(spike_mem_out),
    .active_group_in(),

    .current_decay(current_decay),
    .voltage_decay(voltage_decay),
    .threshold(threshold),
    .new_inference_start(start_instruction),
    .detection(detection_computed),

    .set_address(set_fifo_neuron_address),
    .dim_output_feature(dim_output_feature),

    .write_en_weight_buffer(write_en_weight_buffer),
    .spike_address(spike_address),
    
	.weight_rd_addr(weight_rd_addr_mux),
	.acc_clear(layer_integrated), .acc_clear_and_go(acc_clear_and_go),
	.convolution_pipe_full(convolution_pipe_full_L1),    
	.layer_id(layer_counter),

    .en_conv_spike(en_conv_spike),
    .en_conv(conv_en && last_spike),

    .spike_out(s1),
    .integrated_neuron(integrated_neuron_1),
    .neuron_lp_voltage(voltage_1),

    .conv_enable(conv_enable),
    .dense_enable(dense_enable),
    .first_input_feature(first_input_feature_computed), 
    .last_input_feature(last_input_feature_out),

   .weight_mem_L1_wren(weight_mem_L1_wren),
   .weight_mem_L1_wr_addr(weight_mem_L1_wr_addr),
   .weight_mem_L1_data_in(weight_mem_L1_data_in),
   .weight_mem_L1_ena(weight_mem_L1_ena),
   .weight_mem_L2_wren(weight_mem_L2_wren),
   .weight_mem_L2_wr_addr(weight_mem_L2_wr_addr),
   .weight_mem_L2_data_in(weight_mem_L2_data_in),
   .weight_mem_L2_ena(weight_mem_L2_ena),
   .weights_buffer_ready(weights_buffer_ready_L1)

	//.weight_debug(weight_debug),
	//.weight_en_debug(weight_en_debug)
    );    
/*
  _     ____            _     ____  
 | |   |  _ \          | |   |___ \ 
 | |   | |_) |  _____  | |     __) |
 | |___|  __/  |_____| | |___ / __/ 
 |_____|_|             |_____|_____|
                                    
*/
wire signed [WIDTH-1:0] voltage_2;
wire conv_en_L2;

assign conv_en_L2 = conv_enable ? en_L2 : 1;

layer_lp
    #(
    .WIDTH(WIDTH),
    .MAX_SYNAPSES(MAX_SYNAPSES),
    .MAX_NEURONS(MAX_NEURONS/2),
    .MAX_DECAY(MAX_DECAY),
    .MAX_INPUT_FEATURE(MAX_INPUT_FEATURE),

	.LAYERS(LAYERS),

    .WEIGHTS_FILE_1(WEIGHTS_FILE_3),
	.WEIGHTS_FILE_2(WEIGHTS_FILE_4),
    .WEIGHT_DEPTH(WEIGHT_DEPTH_12)
    )
layer_lp_l2_i
    (
    .clk(clk), .rst(rst),
    .en(layer_enable_dd && conv_en_L2),
    .spike_in(spike_mem_out),
    .active_group_in(),

    .layer_type(layer_type),
    .current_decay(current_decay),
    .voltage_decay(voltage_decay),
    .threshold(threshold),
    .new_inference_start(start_instruction),
    .detection(detection_computed),

    .set_address(set_fifo_neuron_address),
    .dim_output_feature(dim_output_feature),

    .write_en_weight_buffer(write_en_weight_buffer),
    .spike_address(spike_address),
    
	.weight_rd_addr(weight_rd_addr_mux),
	.acc_clear(layer_integrated), .acc_clear_and_go(acc_clear_and_go),
	.convolution_pipe_full(convolution_pipe_full_L2),    
	.layer_id(layer_counter),  

    .en_conv_spike(en_conv_spike), 
    .en_conv(conv_en && last_spike), 
    
    .spike_out(s2),
    .neuron_lp_voltage(voltage_2),
	.integrated_neuron(integrated_neuron_2),

    .conv_enable(conv_enable),
    .dense_enable(dense_enable),
    .first_input_feature(first_input_feature_computed), 
    .last_input_feature(last_input_feature_out),
    
   .weight_mem_L1_wren(weight_mem_L3_wren),
   .weight_mem_L1_wr_addr(weight_mem_L3_wr_addr),
   .weight_mem_L1_data_in(weight_mem_L3_data_in),
   .weight_mem_L1_ena(weight_mem_L3_ena),
   .weight_mem_L2_wren(weight_mem_L4_wren),
   .weight_mem_L2_wr_addr(weight_mem_L4_wr_addr),
   .weight_mem_L2_data_in(weight_mem_L4_data_in),
   .weight_mem_L2_ena(weight_mem_L4_ena),
   .weights_buffer_ready(weights_buffer_ready_L2)
    );  

wire weights_buffer_ready, weights_buffer_ready_L1, weights_buffer_ready_L2;

assign weights_buffer_ready = weights_buffer_ready_L1 || weights_buffer_ready_L2;

assign convolution_pipe_full = convolution_pipe_full_L1 || convolution_pipe_full_L2;

wire valid12; 
assign valid12 = valid_spike_1 && valid_spike_2;

/////////////////////////////////////////////////
//    ____                  _                  //
//   / ___|___  _   _ _ __ | |_ ___ _ __ ___   //
//  | |   / _ \| | | | '_ \| __/ _ \ '__/ __|  //
//  | |__| (_) | |_| | | | | ||  __/ |  \__ \  //
//   \____\___/ \__,_|_| |_|\__\___|_|  |___/  //
//											   //
/////////////////////////////////////////////////                                          

// counters definition
reg [LAYERS_LOG2-1:0] layer_counter;
reg [clogb2(MAX_NEURONS/2-1)-1:0] neuron_cnt; 
wire [12:0] spike_wr_addr;

/////// SPIKE MEMORY WRITE PORT COUNTER /////////////////////////////////////////////////

wire spike_written;
reg [clogb2(LAYERS-1)-1:0] spike_written_counter;
parameter MAX_SYNAPSES_CONV = 512;
reg [clogb2(MAX_SYNAPSES_CONV)-1:0] SYNAPSES;

//ATTENZIONE QUI

always @(posedge clk)
    if(rst)
        SYNAPSES <= 98/4-1;
    else if (spike_written_d) begin
        if (spike_written_counter == 0)
            SYNAPSES <= 98/4-1;
        else 
            SYNAPSES <= SYNAPSES_instr;
    end

reg spike_written_d;
always @(posedge clk)
    if (rst)
        spike_written_d <= 0;
    else
        spike_written_d <= spike_written;


always @(posedge clk)
    if (rst)
		spike_written_counter <= 0;
	else if(spike_written) begin
            if (spike_written_counter < LAYERS - 1) 
                spike_written_counter <= spike_written_counter + 1'b1;
            else 
                spike_written_counter <= 0;
    end

/////// NEURON COUNTER /////////////////////////////////////////////////

wire [clogb2(MAX_NEURONS/2-1)-1:0] NEURON;
wire dense_enable;

assign NEURON = (dense_enable) ? (neuron+1)/2-1 : 0;

// neuron_cnt increases when the weights of a neuron are read
wire stream_out_done;
assign stream_out_done = stream_out_done_2 || stream_out_done_1;
always @(posedge clk)
    if(rst)
        neuron_cnt <= 0;
    else
        if (stream_out_done) begin
            if ((neuron_cnt < NEURON) ) 
                neuron_cnt <= neuron_cnt + 1'b1;
            else
                neuron_cnt <= 0;
        end
                
assign layer_dispatched = stream_out_done && (neuron_cnt == NEURON); 

/////// LAYER COUNTER /////////////////////////////////////////////////
always @(posedge clk)
    if (rst)
        layer_counter <= 0;
    else begin
        if (layer_integrated)
			if(layer_counter < LAYERS - 1) 
        		layer_counter <= layer_counter + 1'b1;
            else 
                layer_counter <= 0;
    end

///////////////////////////////////////////////////////////
//                            _       _   _              //
//   ___ ___  _ ____   _____ | |_   _| |_(_) ___  _ __   //
//  / __/ _ \| '_ \ \ / / _ \| | | | | __| |/ _ \| '_ \  //
// | (_| (_) | | | \ V / (_) | | |_| | |_| | (_) | | | | //
//  \___\___/|_| |_|\_/ \___/|_|\__,_|\__|_|\___/|_| |_| //
//                                                       //
///////////////////////////////////////////////////////////

wire [15:0] spike_mem_in_16;
wire conv_enable;
wire new_layer_en;
wire [15:0] spike_address;
wire set_fifo_neuron_address;
reg en_conv;
wire first_input_feature;
wire last_output_feature;
wire output_feature_finish;
wire [clogb2(SPIKE_MEM_DEPTH)-1 : 0] spike_mem_rd_addr_conv;
wire conv_en;
wire [3:0] dim_output_feature;

assign conv_enable = (layer_type == 2'b01) ? 1 : 0;
assign dense_enable = (layer_type == 2'b00) ? 1 : 0;
assign polling_enable = (layer_type == 2'b10) ? 1 : 0;

always @(posedge clk)
    if (rst)
        en_conv <= 0;
    else if (dense_enable | convolution_finish)
        en_conv <= 0;
    else if (((layer_counter != 0 && layer_integrated_dd)||(spike_written_counter == 1 && spike_written_d)) && conv_enable)
        en_conv <= 1;

conv_controll #(
    .MAX_KERNEL(MAX_KERNEL),
    .MAX_INPUT_FEATURE(MAX_INPUT_FEATURE),
    .MAX_NUMBER_INPUT_FEATURE(MAX_NUMBER_INPUT_FEATURE),
    .MAX_NUMBER_OUTPUT_FEATURE(MAX_NUMBER_OUTPUT_FEATURE),
    .WEIGHT_DEPTH(WEIGHT_DEPTH_12)
) conv_controll_i
(
    .clk(clk),
    .rst(rst),
    .en(en_conv),
    .conv_enable(conv_enable),
    .stride(stride),
    
    .dim_input_feature(size_input_feature),
    .dim_kernel(kernel_size),
    .input_feature_row(spike_mem_out_16),
    .number_input_feature(number_input_feature),
    .number_output_feature(number_output_feature),
    .first_input_feature(first_input_feature),
    .base_address_weights(BASE_ADDRESS_WEIGHTS*layer_counter),
    .weights_buffer_ready(weights_buffer_ready),
    .dim_output_feature(dim_output_feature),
    
    .spike_address(spike_address),
    .convolution_finish(convolution_finish),
    .output_feature_finish(output_feature_finish),
    .set_fifo_neuron_address(set_fifo_neuron_address),
    .new_kernel (new_kernel),
    .spike_written(spike_written),

    .spike_check(spike_check),
    .write_en_weight_buffer(write_en_weight_buffer),
    .weight_rd_addr(weight_rd_addr_conv),
    .en_L1(en_L1),
    .en_L2(en_L2),
    .last_input_feature(last_input_feature),
    .spike_mem_rd_addr(spike_mem_rd_addr_conv),
    .conv_en(conv_en),
    .last_spike(last_spike)
);

//////////////////////////////////////////////////
//   _        _ __   _______ ____  ____         //
//  | |      / \\ \ / / ____|  _ \/ ___|        //
//  | |     / _ \\ V /|  _| | |_) \___ \        //
//  | |___ / ___ \| | | |___|  _ < ___) |       //
//  |_____/_/   \_\_| |_____|_| \_\____/        //
//    ____ ___  _   _ _____ ____   ___  _       //
//   / ___/ _ \| \ | |_   _|  _ \ / _ \| |      //
//  | |  | | | |  \| | | | | |_) | | | | |      //
//  | |__| |_| | |\  | | | |  _ <| |_| | |___   //
//   \____\___/|_| \_| |_| |_| \_\\___/|_____|  //
//   ____ ___ ____ _   _    _    _     ____     //
//  / ___|_ _/ ___| \ | |  / \  | |   / ___|    //
//  \___ \| | |  _|  \| | / _ \ | |   \___ \    //
//   ___) | | |_| | |\  |/ ___ \| |___ ___) |   //
//  |____/___\____|_| \_/_/   \_\_____|____/    //
//                                              //
//////////////////////////////////////////////////

/////// LAYER ENABLE /////////////////////////////////////////////////
reg layer_enable, layer_enable_d, layer_enable_dd;
always @(posedge clk) begin
    if (rst)
        layer_enable <= 1'b0;
    else if (en_conv || stream_out_1 || stream_out_2)
        layer_enable <= 1'b1;
    else if (convolution_finish || (stream_out_done && (neuron_cnt == NEURON)))
        layer_enable <= 1'b0;
end 

always @(posedge clk)
    if (rst) begin
		layer_enable_d  <= 0;
		layer_enable_dd <= 0;
		end 
	else begin
		layer_enable_d  <= layer_enable;
		layer_enable_dd <= layer_enable_d;
		end

/////// LAYER ACCUMULATOR /////////////////////////////////////////////

wire convolution_valid;

// The conv module valid bit "convolution_pipe_full" is:  en -|_|-|_|-|_|-|_|-|_|- convolution_pipe_full
// By counting the number of clock cycles it is at logic-1, and comparing the value with 
// the number of memory reads per convolution (provided by the stack), it is possible to 
// generate the convolution valid signal "convolution_valid", which is used to: 
//  1. clear the accumulator register
//  2. enable the LIF neuron integration

assign words_to_read = layer_counter[0]? words_to_read_2 : words_to_read_1;

reg [clogb2(MAX_SYNAPSES/4-1)-1:0] convolution_valid_cnt;
always @(posedge clk)
    if (rst || conv_enable)
        convolution_valid_cnt <= 0;
    else if (convolution_pipe_full) begin
            if(convolution_valid_cnt < words_to_read)
                convolution_valid_cnt <= convolution_valid_cnt + 1'b1;
            else
                convolution_valid_cnt <= 0;
    end
 
assign convolution_valid = (convolution_valid_cnt == words_to_read) && convolution_pipe_full; 

// Moreover, it is necessary to assess when each layer's computation terminates
// to clear the accumulation register

wire integrated_neuron_1, integrated_neuron_2;
assign integrated_neuron = integrated_neuron_1; // integrated_neuron 1 and 2 are the same

// Integrated neurons counter

wire [clogb2(MAX_INPUT_FEATURE*MAX_INPUT_FEATURE)-1:0] NEURON_CONV;

// Istanziazione del blocco DSP
    SB_MAC16 #(
        .TOPOUTPUT_SELECT(2'b11),
        .BOTOUTPUT_SELECT(2'b11),
        .TOPADDSUB_UPPERINPUT(1'b1),
        .TOPADDSUB_LOWERINPUT(2'b10),
        .BOTADDSUB_UPPERINPUT(1'b1),
        .BOTADDSUB_LOWERINPUT(2'b10),
        .TOPADDSUB_CARRYSELECT(2'b10)
    ) neuron_conv (
        .A(dim_output_feature),
        .B(dim_output_feature),
        .O(square_dim_output_feature),
        .CLK(clk),
        .CE(1'b1),
        .IRSTTOP(rst),
        .IRSTBOT(rst)
    );

wire[31:0] square_dim_output_feature;
assign NEURON_CONV = square_dim_output_feature[7:0] - 1;

reg [clogb2(MAX_NEURONS/2-1)-1:0] integrated_neurons_cnt; 
wire [7:0] neuron_limit = dense_enable ? NEURON : NEURON_CONV;
wire next_reset_cond     = conv_enable && !last_input_feature_out;

always @(posedge clk) begin
    if (rst)
        integrated_neurons_cnt <= 0;
    else if (integrated_neuron) begin
        if (next_reset_cond)
            integrated_neurons_cnt <= 0;
        else if (integrated_neurons_cnt < neuron_limit)
            integrated_neurons_cnt <= integrated_neurons_cnt + 1'b1;
        else
            integrated_neurons_cnt <= 0;
    end
end

reg output_feature_integrated;
wire finish_integrated_neuron = integrated_neurons_cnt == neuron_limit;

always @(posedge clk)
    if (rst)
        output_feature_integrated <= 0;
    else begin
        if(integrated_neuron && last_input_feature_out && finish_integrated_neuron)
            output_feature_integrated <= 1;
        else 
            output_feature_integrated <= 0;
    end

reg [clogb2(MAX_NUMBER_OUTPUT_FEATURE)-1:0] output_feature_integrated_cnt;

always @(posedge clk) begin
    if (rst || layer_integrated_conv_d)
        output_feature_integrated_cnt <= 0;
    else if (output_feature_integrated) begin
        if (output_feature_integrated_cnt >= number_output_feature)
            output_feature_integrated_cnt <= 0;
        else
            output_feature_integrated_cnt <= output_feature_integrated_cnt + 2;
    end
end

wire [clogb2(MAX_INPUT_FEATURE)-1:0] number_output_feature_minus_two = number_output_feature - 2;
wire [clogb2(MAX_INPUT_FEATURE)-1:0] number_output_feature_minus_one = number_output_feature - 1;

assign last_output_feature = (output_feature_integrated_cnt >= number_output_feature_minus_two);

reg layer_integrated_conv;

always @(posedge clk)
    if (rst)
        layer_integrated_conv <= 0;
    else begin
        if(output_feature_integrated && last_output_feature)
           layer_integrated_conv <= 1;
        else
            layer_integrated_conv <= 0;
    end

reg layer_integrated_dense;
always @(posedge clk)
    if (rst)
        layer_integrated_dense <= 0;
    else begin
        if(integrated_neuron && finish_integrated_neuron)
           layer_integrated_dense <= 1;
        else
            layer_integrated_dense <= 0;
    end

reg layer_integrated_conv_d;
always @(posedge clk)
    if (rst) begin
        layer_integrated_conv_d  <= 0;
    end 
    else begin
        layer_integrated_conv_d  <= layer_integrated_conv;
    end

assign layer_integrated = conv_enable ? layer_integrated_conv_d : layer_integrated_dense;

reg layer_integrated_d, layer_integrated_dd;

always @(posedge clk)
    if (rst) begin
        layer_integrated_d  <= 0;
        layer_integrated_dd <= 0;
    end 
    else begin
        layer_integrated_d  <= layer_integrated;
        layer_integrated_dd <= layer_integrated_d;
    end

//////////////////////////////
//      _             _     //
//  ___| |_ __ _  ___| | __ //
// / __| __/ _` |/ __| |/ / //
// \__ \ || (_| | (__|   <  //
// |___/\__\__,_|\___|_|\_\ //
//                          //
//////////////////////////////

// it stores the addresses of the active spike groups
// At every neuron integration:
//  - spike_rd_addr = stack_data_out
//  - weight_rd_addr = {neuron_cnt,stack_data_out}
// By doing so only the active groups are read, enabling
// both higher performances and least power wastes

wire stream_out_done_1, stream_out_done_2;
wire stream_out_1, stream_out_2;
wire [clogb2(MAX_SYNAPSES/4-1)-1:0] words_to_read_1, words_to_read_2, words_to_read;
wire empty, empty_1, empty_2;
reg en_d;

always @(posedge clk)
    if (rst) begin
        en_d <= 0;
    end
    else begin
        en_d <= en;
    end

wire stack_en_1;
wire valid_active_group_1, valid_active_group_2;
wire valid_active_spike = (valid_active_group) && (active_spike);

assign stack_en_1 = valid_active_spike && (layer_counter[0] || en_d); 
assign stream_out_1 = (spike_written && ~spike_written_counter[0]) || (stream_out_done_1  && (neuron_cnt != NEURON));

wire stack_en_2;
assign stack_en_2 = valid_active_spike && (~layer_counter[0] && !en_d);
assign stream_out_2 = (spike_written && spike_written_counter[0]) || (stream_out_done_2 && (neuron_cnt != NEURON));


stack_new
#(
.DATA_WIDTH(clogb2(MAX_SYNAPSES/4-1)),
.DEPTH(MAX_SYNAPSES/4)
 )
stack_1
 (
.clk(clk), .rst(rst),
.din(spike_wr_addr),
.wr_en(stack_en_1), 
.clear(layer_integrated && ~layer_counter[0]),
.stream_out(stream_out_1),

.dout(spike_rd_addr_1),
.done(stream_out_done_1),
.active_entries(words_to_read_1),
.empty(empty_1)
);


stack_new
#(
.DATA_WIDTH(clogb2(MAX_SYNAPSES/4-1)),
.DEPTH(MAX_SYNAPSES/4)
 )
stack_2
 (
.clk(clk), .rst(rst),
.din(spike_wr_addr),
.wr_en(stack_en_2), 
.clear(layer_integrated && layer_counter[0]),
.stream_out(stream_out_2),

.dout(spike_rd_addr_2),
.done(stream_out_done_2),
.active_entries(words_to_read_2),
.empty(empty_2)
);


// stack enable to stream out the rd_address for spike_mem and weight_mem
wire [clogb2(MAX_SYNAPSES_CONV/4-1)-1:0] spike_rd_addr;
assign spike_rd_addr = layer_counter[0]?spike_rd_addr_2:spike_rd_addr_1;
assign empty = layer_counter[0]?empty_2:empty_1;

/////////////////////////////////////////////////////  
//            _ _                                  //
//  ___ _ __ (_) | _____   _ __ ___   ___ _ __ ___ //
// / __| '_ \| | |/ / _ \ | '_ ` _ \ / _ \ '_ ` _  //
// \__ \ |_) | |   <  __/ | | | | | |  __/ | | | | //
// |___/ .__/|_|_|\_\___| |_| |_| |_|\___|_| |_| | //
//     |_|                                         //
///////////////////////////////////////////////////// 

wire [3:0] spike_mem_out_1;
wire [clogb2(MAX_SYNAPSES_CONV/4-1)-1:0] spike_rd_addr_1;
wire spike_wr_en_1; 
wire [15:0] spike_mem_out_16_1, spike_mem_out_16_2;

wire [3:0] spike_mem_out_2;
wire [clogb2(MAX_SYNAPSES_CONV/4-1)-1:0] spike_rd_addr_2;
wire spike_wr_en_2; 

assign spike_wr_en_1 = (layer_counter[0]) || en;

assign spike_wr_en_2 =  ~layer_counter[0];

wire [clogb2(SPIKE_MEM_DEPTH)-1:0] spike_rd_addr_1_mux, spike_rd_addr_2_mux, spike_wr_addr_mux;
assign spike_rd_addr_1_mux = i_spike_mem_rd_en[0] ? i_spike_mem_adr : 
                            conv_enable ? spike_mem_rd_addr_conv : spike_rd_addr_1;
assign spike_rd_addr_2_mux = i_spike_mem_rd_en[1] ? i_spike_mem_adr : 
                            conv_enable ? spike_mem_rd_addr_conv : spike_rd_addr_2;
assign o_spike_mem_dat = {spike_mem_out_4,spike_mem_out_4};

assign spike_wr_addr_mux = spike_wr_addr;

wire [12:0] spike_wr_addr_1, spike_wr_addr_2;

wire spike_written_1, spike_written_2;

wire last_layer;
assign last_layer = (layer_counter == LAYERS -1) ? 1 : 0;

parameter SPIKE_MEM_DEPTH = 256;

spike_mem #(
    .SPIKE_MEM_WIDTH(16),
    .SPIKE_MEM_DEPTH(SPIKE_MEM_DEPTH),
    .MAX_SYNAPSES(MAX_SYNAPSES)
)spike_mem(
    .clk(clk),
    .rst(rst),
    .layer_counter(layer_counter[0]),
    .valid_encoding(en),
    .s1(en? s1_encoding : s1),
    .valid_s1(((valid_spike_1) && !last_layer)|| en),
    .s2(en? s2_encoding : s2),
    .valid_s2(((valid_spike_2) && !last_layer)|| en),
    .dense_enable(dense_enable || dense_next),
    .conv_enable(conv_enable),
    .next_dim_input_feature(en && conv_enable ? size_input_feature : next_dim_input_feature),
    .output_feature_finish(output_feature_integrated),
    .en_L2(en_L2_out),
    .SYNAPSES(SYNAPSES),
    .spike_rd_addr_1(spike_rd_addr_1_mux),
    .spike_rd_addr_2(spike_rd_addr_2_mux),
    .last_layer(last_layer),
    .spike_wr_addr(spike_wr_addr),
    .spike_wr_en_in_1(spike_wr_en_1),
    .spike_wr_en_in_2(spike_wr_en_2),
    .active_spike(active_spike),
    .spike_mem_out_16(spike_mem_out_16),
    .spike_mem_out_4(spike_mem_out_4),
    .spike_written(spike_written),
    .valid_active_group(valid_active_group)
    );

wire [3:0] spike_mem_out, spike_mem_out_4;
wire [15:0] spike_mem_out_16;
assign spike_mem_out = conv_enable ? 4'b1111 : 
                        empty ? 4'b0: spike_mem_out_4;

wire [WEIGHT_ADDRESS_SIZE-1:0] weight_rd_addr_dense;
wire [WEIGHT_ADDRESS_SIZE-1:0] weight_rd_addr_conv;
wire [WEIGHT_ADDRESS_SIZE-1:0] weight_rd_addr_mux;

assign weight_rd_addr_mux = (conv_enable) ? weight_rd_addr_conv : weight_rd_addr_dense;

localparam LAYERS_BITS       = clogb2(LAYERS)-1;
wire [WEIGHT_ADDRESS_SIZE-LAYERS_BITS-2:0] last_address;
assign last_address = (neuron_cnt << bit_for_spike) + spike_rd_addr;
assign weight_rd_addr_dense = {1'b0, layer_counter, last_address};

///////////////////////////////////////////
//   ___  _   _ _____ ____  _   _ _____  //
//  / _ \| | | |_   _|  _ \| | | |_   _| //
// | | | | | | | | | | |_) | | | | | |   //
// | |_| | |_| | | | |  __/| |_| | | |   //
//  \___/ \___/  |_| |_|    \___/  |_|   //
//  ____  _   _ _____ _____ _____ ____   //
// | __ )| | | |  ___|  ___| ____|  _ \  //
// |  _ \| | | | |_  | |_  |  _| | |_) | //
// | |_) | |_| |  _| |  _| | |___|  _ <  //
// |____/ \___/|_|   |_|   |_____|_| \_\ //
//                                       //
///////////////////////////////////////////

wire output_buffer_wr_en;
wire [31:0] output_buffer_din;
assign output_buffer_wr_en = integrated_neuron && last_layer;
assign output_buffer_din = {voltage_2,voltage_1};

BRAM_singlePort_readFirst #(
  .RAM_WIDTH(2*WIDTH),            
  .RAM_DEPTH(MAX_NEURONS/8),    //ho ipotizzato 1/8 del massimo nunmero di neuroni          
  .RAM_PERFORMANCE("LOW_LATENCY"), 
  .INIT_FILE("")          
)
	output_buffer
(
  .addra(integrated_neurons_cnt),   
  .addrb(output_buffer_addr),  
  .dina(output_buffer_din),   
  .clk(clk),      
  .wea(output_buffer_wr_en),      
  .ena(output_buffer_wr_en),      
  .enb(output_buffer_ren),      
  .rst(rst),      
  .regceb(1'b1),
  
  .doutb(output_buffer_out)   
    );

`ifdef CONFIGURABILITY	
	assign valid = layer_integrated && layer_counter == layers-1;	
	assign valid_spike = valid12 && layer_counter == layers-1;
`else 
	assign valid = (layer_integrated && last_layer);
	assign valid_spike = valid12 && last_layer;
`endif
	

//  The following function calculates the address width based on specified RAM depth
	function integer clogb2;
	  input integer depth;
		for (clogb2=0; depth>0; clogb2=clogb2+1)
		  depth = depth >> 1;
	endfunction 
	
	function integer max;
	  input integer j,k;
		if(j>k)
		  max = j;
	endfunction 	

	function integer max4;
        input integer a, b, c, d;
        begin
            max4 = (a > b ? a : b) > (c > d ? c : d) ? (a > b ? a : b) : (c > d ? c : d);
        end
    endfunction

endmodule