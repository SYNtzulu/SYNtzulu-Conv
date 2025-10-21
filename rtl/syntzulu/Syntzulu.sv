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
    parameter WEIGHT_DEPTH_34 = 8192
)
(
    input clk_enc, clk_snn, rst,
    input en,
    input signed [15:0] data_in,
    input detect,
	input encoding_bypass,
    
    output valid,
    output signed [WIDTH-1:0] v,
    output signed [WIDTH-1:0] f1,
    output signed [WIDTH-1:0] f2,
    output signed [WIDTH-1:0] f3,
    output signed [WIDTH-1:0] f4,

    output signed [WIDTH-1:0] neuron_lp_voltage,
	output integrated_neuron,

    // weight mem 1
    input [7:0] weight_mem_L1_wren,
    input [clogb2(WEIGHT_DEPTH_12-1)-1:0] weight_mem_L1_wr_addr,
    input [16-1:0] weight_mem_L1_data_in,
    output [16-1:0] weight_mem_L1_data_out,
    input weight_mem_L1_ena,

    // weight mem 2
    input [7:0] weight_mem_L2_wren,
    input [clogb2(WEIGHT_DEPTH_12-1)-1:0] weight_mem_L2_wr_addr,
    input [16-1:0] weight_mem_L2_data_in,
    output [16-1:0] weight_mem_L2_data_out,
    input weight_mem_L2_ena,

    // weight mem 3
    input [7:0] weight_mem_L3_wren,
    input [clogb2(WEIGHT_DEPTH_34-1)-1:0] weight_mem_L3_wr_addr,
    input [16-1:0] weight_mem_L3_data_in,
    output [16-1:0] weight_mem_L3_data_out,
    input weight_mem_L3_ena,

    // weight mem 4
    input [7:0] weight_mem_L4_wren,
    input [clogb2(WEIGHT_DEPTH_34-1)-1:0] weight_mem_L4_wr_addr,
    input [16-1:0] weight_mem_L4_data_in,
    output [16-1:0] weight_mem_L4_data_out,
    input weight_mem_L4_ena,
	
	//spike mem 1 & 2
	output wire [7:0] o_spike_mem_dat,
	input wire [7:0] i_spike_mem_adr,
	input wire [1:0] i_spike_mem_rd_en,	
	input wire [1:0] i_spike_mem_wr_en,
	input wire [3:0] i_spike_mem_dat,
	// sample mem
	output wire [15:0] o_sample_mem_dat,	
	input wire [7:0] i_sample_mem_adr,
	input wire       i_sample_mem_rd_en,	 
	input wire        i_sample_mem_wr_en,
	input wire [15:0] i_sample_mem_dat,
	// # layers and channels
	input wire [clogb2(MAX_SYNAPSES-1)-1:0] snn_input_channels, 
	input wire [clogb2(MAX_NEURONS-1)-1:0] neuron_1, neuron_2, neuron_3, neuron_4, 
	/*neuron_5, neuron_6, neuron_7, neuron_8,*/
	input wire [2:0] layers,
	// output buffer access
	input output_buffer_ren,
	input [7:0] output_buffer_addr,
	output [31:0] output_buffer_out
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

    //.spike_bin(spike_bin), --- IGNORE ---
    //.valid_bin(valid_bin), --- IGNORE ---
    //.active_group_out_bin(active_group_out_bin), --- IGNORE ---

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

wire valid_potential;
wire [SPIKE-1:0] spike_out_snn;
wire valid_spike;

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
    //.en(valid_bin),
    .en(valid_encoding),
    .s1_encoding(s1_encoding),
    .s2_encoding(s2_encoding),
    //.spike_in(spike_bin),
    //.active_group_in(active_group_out_bin),
    .valid(valid_potential),
    .valid_spike(valid_spike),
    .spike_out(spike_out_snn),
    .integrated_neuron(integrated_neuron),
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
    .o_spike_mem_dat(o_spike_mem_dat),
    .i_spike_mem_adr(i_spike_mem_adr),
    .i_spike_mem_rd_en(i_spike_mem_rd_en),
    .i_spike_mem_wr_en(i_spike_mem_wr_en),
    .i_spike_mem_dat(i_spike_mem_dat),
    .snn_input_channels(snn_input_channels),
    .layers(layers),
    .output_buffer_ren(output_buffer_ren),
    .output_buffer_addr(output_buffer_addr),
    .output_buffer_out(output_buffer_out),
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
 
assign valid = valid_potential;
   
//  The following function calculates the address width based on specified RAM depth
function integer clogb2;
  input integer depth;
    for (clogb2=0; depth>0; clogb2=clogb2+1)
      depth = depth >> 1;
endfunction   
    
endmodule
