`timescale 1ns / 1ps

module Syntzulu
#(

	parameter ENCODING_BYPASS = 0,
    parameter CHANNELS = 128,
    parameter ORDER = 2,
    parameter WINDOW = 8192,
    parameter REF_PERIOD = 16,
    parameter DW = 15,
    
    parameter WIDTH = 16,
    parameter N_CLASSES = 10,
    parameter TIME_STEPS = 48,

	parameter MAX_SYNAPSES = 128,
	parameter MAX_NEURONS = 128,

    parameter LAYERS = 4, //è pari alla profondità della memoria delle istruzioni
    parameter MAX_DECAY = 4096,
    parameter MAX_THRESHOLD = 65536,

    parameter INSTR_WIDTH = 64,
    parameter INSTR_FILE = "",

    parameter WEIGHTS_FILE_1 = "",
    parameter WEIGHTS_FILE_2 = "",
    parameter WEIGHTS_FILE_3 = "",
    parameter WEIGHTS_FILE_4 = "",
    
    parameter WEIGHT_DEPTH_12 = 8192,
    parameter WEIGHT_DEPTH_34 = 8192,

    parameter BUFFER_WIDTH = 32
)
(
    input clk_enc, clk_snn, rst,
    input en,
    input signed [15:0] data_in,
    input detect,
	input encoding_bypass,
    
    output valid,
    output valid_class,

	output integrated_neuron,
    //output new_instruction,

    // weight mem 1
    input weight_mem_L1_wren,
    input [clogb2(WEIGHT_DEPTH_12-1)-1:0] weight_mem_L1_wr_addr,
    input [16-1:0] weight_mem_L1_data_in,
    output [16-1:0] weight_mem_L1_data_out,
    input weight_mem_L1_ena,

    // weight mem 2
    input weight_mem_L2_wren,
    input [clogb2(WEIGHT_DEPTH_12-1)-1:0] weight_mem_L2_wr_addr,
    input [16-1:0] weight_mem_L2_data_in,
    output [16-1:0] weight_mem_L2_data_out,
    input weight_mem_L2_ena,

    // weight mem 3
    input weight_mem_L3_wren,
    input [clogb2(WEIGHT_DEPTH_34-1)-1:0] weight_mem_L3_wr_addr,
    input [16-1:0] weight_mem_L3_data_in,
    output [16-1:0] weight_mem_L3_data_out,
    input weight_mem_L3_ena,

    // weight mem 4
    input weight_mem_L4_wren,
    input [clogb2(WEIGHT_DEPTH_34-1)-1:0] weight_mem_L4_wr_addr,
    input [16-1:0] weight_mem_L4_data_in,
    output [16-1:0] weight_mem_L4_data_out,
    input weight_mem_L4_ena,
/*
    input wire wen_instr,
    input wire [clogb2(WEIGHT_DEPTH_12-1)-1:0] wr_addr_instr,
    input wire [15:0] wr_data_instr,
	
	//spike mem 1 & 2
	output wire [31:0] o_spike_mem_dat,
	input wire [7:0] i_spike_mem_adr,
	input wire [1:0] i_spike_mem_rd_en,	
	input wire [1:0] i_spike_mem_wr_en,
	input wire [3:0] i_spike_mem_dat,

	// sample mem
	output wire [15:0] o_sample_mem_dat,	
	input wire [7:0] i_sample_mem_adr,
	input wire       i_sample_mem_rd_en,	 
	input wire        i_sample_mem_wr_en,
	input wire [15:0] i_sample_mem_dat,*/

	// output buffer access
	input output_buffer_ren,
	input [7:0] output_buffer_addr,
	output [BUFFER_WIDTH-1:0] output_buffer_out
    );

 localparam SPIKE  = 4;

/////////////////////////////////////////////////////////////////////////// 
//  _____ _   _  ____ ___  ____ ___ _   _  ____   ____  _     ___ _____  //
// | ____| \ | |/ ___/ _ \|  _ \_ _| \ | |/ ___| / ___|| |   / _ \_   _| //
// |  _| |  \| | |  | | | | | | | ||  \| | |  _  \___ \| |  | | | || |   //
// | |___| |\  | |__| |_| | |_| | || |\  | |_| |  ___) | |__| |_| || |   //
// |_____|_| \_|\____\___/|____/___|_| \_|\____| |____/|_____\___/ |_|   //
//                                                                       //                                    
///////////////////////////////////////////////////////////////////////////
    
 wire [SPIKE-1:0] spike_bin;
 wire valid_bin;
 wire active_group_out_bin;
 wire input_buffer_valid;

encoding_slot #(
	.BYPASS(ENCODING_BYPASS),    
	.CHANNELS(CHANNELS),
    .ORDER(ORDER),
    .WINDOW(WINDOW),
    .REF_PERIOD(REF_PERIOD),
    .DW(DW)
)
encoding_slot_i
(   
    .clk(clk_enc), 
    .rst(rst),
    .en(en),
    .data_in(data_in),
    .detect(detect),

    .s1_encoding(s1_encoding),
    .s2_encoding(s2_encoding),
    .valid_encoding(valid_encoding),

    .inference_done(valid_potential),

    .o_sample_mem_dat(o_sample_mem_dat),
    .i_sample_mem_adr(i_sample_mem_adr),
    .i_sample_mem_rd_en(i_sample_mem_rd_en),
    .i_sample_mem_wr_en(i_sample_mem_wr_en),
    .i_sample_mem_dat(i_sample_mem_dat),
    .bypass(encoding_bypass),
    .input_buffer_valid(input_buffer_valid)
    );

//////////////////////////////////////////////
//                                          //
//  ____        _ _    _                    //
// / ___| _ __ (_) | _(_)_ __   __ _        //
// \___ \| '_ \| | |/ / | '_ \ / _` |       //
//  ___) | |_) | |   <| | | | | (_| |       //
// |____/| .__/|_|_|\_\_|_| |_|\__, |       //
//       |_|                   |___/        //
//  _   _                      _            //
// | \ | | ___ _   _ _ __ __ _| |           //
// |  \| |/ _ \ | | | '__/ _` | |           //
// | |\  |  __/ |_| | | | (_| | |           //
// |_| \_|\___|\__,_|_|  \__,_|_|           //
//  _   _      _                      _     //
// | \ | | ___| |___      _____  _ __| | __ //
// |  \| |/ _ \ __\ \ /\ / / _ \| '__| |/ / //
// | |\  |  __/ |_ \ V  V / (_) | |  |   <  //
// |_| \_|\___|\__| \_/\_/ \___/|_|  |_|\_\ //
//                                          //
//                                          //
//////////////////////////////////////////////

wire valid_snn;
wire [SPIKE-1:0] spike_out_snn;
wire valid_spike;
wire s1, s2;
wire [WIDTH-1:0] voltage_1, voltage_2;

snn_lp
    #(
    .WIDTH(WIDTH),
    
	.MAX_SYNAPSES(MAX_SYNAPSES),
	.MAX_NEURONS(MAX_NEURONS),
    .LAYERS(LAYERS),
    .MAX_DECAY(MAX_DECAY),
    .MAX_THRESHOLD(MAX_THRESHOLD),

    .INSTR_WIDTH(INSTR_WIDTH),
    .INSTR_FILE(INSTR_FILE),
    .WEIGHTS_FILE_1(WEIGHTS_FILE_1),
    .WEIGHTS_FILE_2(WEIGHTS_FILE_2),
    .WEIGHTS_FILE_3(WEIGHTS_FILE_3),
    .WEIGHTS_FILE_4(WEIGHTS_FILE_4),

    .WEIGHT_DEPTH_12(WEIGHT_DEPTH_12),
    .WEIGHT_DEPTH_34(WEIGHT_DEPTH_34)
    )
snn_lp_i
    (
    .clk(clk_snn),
    .rst(rst),
    .en(valid_encoding),
    .s1_encoding(s1_encoding),
    .s2_encoding(s2_encoding),
    .valid(valid_snn),
    .valid_spike(valid_spike),
    .spike_out(spike_out_snn),
    .reset_potential(reset_potential),
    .integrated_neuron(integrated_neuron),
    //.new_instruction(new_instruction),
    .weight_mem_L1_wren(weight_mem_L1_wren),
    .weight_mem_L1_wr_addr(weight_mem_L1_wr_addr),
    .weight_mem_L1_data_in(weight_mem_L1_data_in),
    .weight_mem_L1_ena(weight_mem_L1_ena),
    .weight_mem_L2_wren(weight_mem_L2_wren),
    .weight_mem_L2_wr_addr(weight_mem_L2_wr_addr),
    .weight_mem_L2_data_in(weight_mem_L2_data_in),
    .weight_mem_L2_ena(weight_mem_L2_ena),
    .weight_mem_L3_wren(weight_mem_L3_wren),
    .weight_mem_L3_wr_addr(weight_mem_L3_wr_addr),
    .weight_mem_L3_data_in(weight_mem_L3_data_in),
    .weight_mem_L3_ena(weight_mem_L3_ena),
    .weight_mem_L4_wren(weight_mem_L4_wren),
    .weight_mem_L4_wr_addr(weight_mem_L4_wr_addr),
    .weight_mem_L4_data_in(weight_mem_L4_data_in),
    .weight_mem_L4_ena(weight_mem_L4_ena),
/*
    .wen_instr(wen_instr),
    .wr_addr_instr(wr_addr_instr),
    .wr_data_instr(wr_data_instr),

    .o_spike_mem_dat(o_spike_mem_dat),
    .i_spike_mem_adr(i_spike_mem_adr),
    .i_spike_mem_rd_en(i_spike_mem_rd_en),
    .i_spike_mem_wr_en(i_spike_mem_wr_en),
    .i_spike_mem_dat(i_spike_mem_dat),*/
    .voltage_1(voltage_1),
    .voltage_2(voltage_2),
    .s1(s1),
    .s2(s2),
    .last_layer(),
    .input_buffer_valid(input_buffer_valid)
    );

///////////////////////////////////////////////////////////////////////////
//   ____  _____ ____ ___  ____ ___ _   _  ____   ____  _     ___ _____  //
//  |  _ \| ____/ ___/ _ \|  _ \_ _| \ | |/ ___| / ___|| |   / _ \_   _| //
//  | | | |  _|| |  | | | | | | | ||  \| | |  _  \___ \| |  | | | || |   //
//  | |_| | |__| |__| |_| | |_| | || |\  | |_| |  ___) | |__| |_| || |   //
//  |____/|_____\____\___/|____/___|_| \_|\____| |____/|_____\___/ |_|   //
//                                                                       //
///////////////////////////////////////////////////////////////////////////

assign valid = valid_snn;
assign valid_class = output_buffer_wr_en;
parameter OUTPUT_BUFFER_DEPTH = MAX_NEURONS/8;

wire output_buffer_wr_en;
wire [BUFFER_WIDTH-1:0] output_buffer_din;
wire [clogb2(OUTPUT_BUFFER_DEPTH)-1:0] output_buffer_wr_addr;
reg reset_potential;

always @(posedge clk_snn)
    if(rst)
        reset_potential <= 1;
    else if(valid_snn)
        reset_potential <= 0;
/*
    decoding_slot #(
        .MAX_NEURONS (MAX_NEURONS),
        .N_CLASSES   (N_CLASSES),
        .INFERENCES  (TIME_STEPS),
        .BUFFER_WIDTH (BUFFER_WIDTH),
        .OUTPUT_BUFFER_DEPTH(OUTPUT_BUFFER_DEPTH)
    ) decoding_slot_i (
        .clk(clk_snn),
        .rst(rst),
        .valid_snn(valid_snn),
        .s1(s1),
        .s2(s2),
        .integrated_neuron(integrated_neuron),
        .last_layer(last_layer),
        .valid_spike_in(valid_spike),
        .integrated_neurons_cnt(integrated_neurons_cnt),
        .voltage_1(voltage_1),
        .voltage_2(voltage_2),
        .reset_potential(reset_potential),
        .output_buffer_din(output_buffer_din),
        .output_buffer_wr_en(output_buffer_wr_en),
        .output_buffer_wr_addr(output_buffer_wr_addr)
    );

    assign output_buffer_out = output_buffer_din;
*/ 
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

    // Output buffer -> IHP SRAM 64x64 (era BRAM inferita/FF). Usati solo
    // BUFFER_WIDTH bit; scrittura sempre @ addr 0, lettura dalla CPU a fine
    // inferenza -> single-port sicuro, latenza di lettura 1 ciclo.
    ihp_ram_64x64 #(
        .DW(BUFFER_WIDTH)
    ) output_buffer (
        .clk   (clk_snn),
        .we    (valid_spike),
        .waddr (6'd0),
        .wdata (voltage_1),
        .re    (output_buffer_ren),
        .raddr (output_buffer_addr[5:0]),
        .rdata (output_buffer_out)
    );
   
//  The following function calculates the address width based on specified RAM depth
function integer clogb2;
  input integer depth;
    for (clogb2=0; depth>0; clogb2=clogb2+1)
      depth = depth >> 1;
endfunction   
    
endmodule
